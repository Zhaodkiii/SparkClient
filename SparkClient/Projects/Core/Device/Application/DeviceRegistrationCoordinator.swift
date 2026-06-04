import Foundation
import UIKit
import UserNotifications

/// 设备登记触发来源（用于日志区分与聚合）。
enum DeviceRegistrationReason: String, Sendable {
    case appLaunch = "app_launch"
    /// 未登录态登录成功后的账号引导登记。
    case signedInBootstrap = "signed_in_bootstrap"
    /// 已登录会话恢复后的冷启动必经登记（APP-STARTUP-000010）。
    case signedInColdLaunch = "signed_in_cold_launch"
    case notificationAuthorization = "notification_authorization"
    case apnsTokenUpdate = "apns_token_update"
    case foregroundPermissionCheck = "foreground_permission_check"
}

/// 读取系统通知授权并触发 APNs 注册（与 PushAdapter 解耦，避免协调器依赖通知基础设施细节）。
@MainActor
protocol DeviceNotificationEnvironment: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func registerForRemoteNotifications()
}

@MainActor
final class SystemDeviceNotificationEnvironment: DeviceNotificationEnvironment {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

@MainActor
protocol DeviceRegistrationExecuting {
    func execute(state: DeviceRegistrationState) async -> RegisterDeviceOutcome
}

extension RegisterDeviceUseCase: DeviceRegistrationExecuting {}

/// 设备信息上送：事件源只更新统一状态，由协调器聚合后最多提交一次完整登记。
@MainActor
final class DeviceRegistrationCoordinator {
    private let registerDevice: any DeviceRegistrationExecuting
    private let deviceCache: DeviceCache
    private let currentUserID: () -> Int?
    private let systemInfo: SparkSystemInfo
    private let notificationEnvironment: any DeviceNotificationEnvironment
    private let logger: Logger

    private var pendingState: DeviceRegistrationState?
    private var lastSubmittedState: DeviceRegistrationState?
    private var pendingReasons: Set<DeviceRegistrationReason> = []

    private var latestApnsTokenHex: String?
    private var cachedAuthorizationStatusRaw: Int?
    private var apnsWaitTask: Task<Void, Never>?
    private var isAwaitingUserAuthorizationApnsToken = false
    private var isSubmissionSuspended = false

    /// 本进程内已成功完成引导级登记的账号（冷启动/登录引导去重，不跨启动复用）。
    private var bootstrapSubmittedAccountIDs: Set<Int> = []
    private var didSubmitAnonymousBootstrapThisLaunch = false

    private var authInvalidationObserver: NSObjectProtocol?

    /// 冷启动/登录引导等待 APNs token（纳秒）。
    private let bootstrapApnsWaitWindowNs: UInt64

    init(
        registerDevice: any DeviceRegistrationExecuting,
        deviceCache: DeviceCache,
        currentUserID: @escaping () -> Int? = { nil },
        systemInfo: SparkSystemInfo? = nil,
        notificationEnvironment: (any DeviceNotificationEnvironment)? = nil,
        bootstrapApnsWaitWindowNs: UInt64 = 1_500_000_000,
        logger: Logger = ConsoleLogger()
    ) {
        self.registerDevice = registerDevice
        self.deviceCache = deviceCache
        self.currentUserID = currentUserID
        self.systemInfo = systemInfo ?? SparkSystemInfo.shared
        self.notificationEnvironment = notificationEnvironment ?? SystemDeviceNotificationEnvironment()
        self.bootstrapApnsWaitWindowNs = bootstrapApnsWaitWindowNs
        self.logger = logger

        authInvalidationObserver = NotificationCenter.default.addObserver(
            forName: AuthSessionInvalidation.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.suspendPendingSubmissions()
            }
        }
    }

    deinit {
        if let authInvalidationObserver {
            NotificationCenter.default.removeObserver(authInvalidationObserver)
        }
    }

    /// 是否存在未完成的匿名冷启动登记（signedOut 首屏清理时不应 reset 掉）。
    var hasPendingAnonymousRegistration: Bool {
        guard pendingReasons.contains(.appLaunch) else { return false }
        guard pendingState?.isAuthenticated != true else { return false }
        return pendingState != nil || apnsWaitTask != nil
    }

    func reset() {
        cancelApnsWait()
        isAwaitingUserAuthorizationApnsToken = false
        isSubmissionSuspended = false
        pendingState = nil
        lastSubmittedState = nil
        pendingReasons.removeAll()
        latestApnsTokenHex = nil
        cachedAuthorizationStatusRaw = nil
        bootstrapSubmittedAccountIDs.removeAll()
        didSubmitAnonymousBootstrapThisLaunch = false
        deviceCache.clearDeviceRegistrationSnapshot()
    }

    func suspendPendingSubmissions() {
        isSubmissionSuspended = true
        cancelApnsWait()
        isAwaitingUserAuthorizationApnsToken = false
        pendingReasons.removeAll()
        logger.info("设备登记已暂停：鉴权失效处理中", module: .network)
    }

    /// App 冷启动（未登录）、已登录冷启动或登录后账号引导：写入意图并由协调器统一 flush（含 APNs 短等待）。
    @discardableResult
    func requestRegister(
        reason: DeviceRegistrationReason,
        accountID: Int? = nil
    ) async -> DeviceRegistrationRequestOutcome {
        guard !isSubmissionSuspended else {
            logger.warning(
                "设备登记阶段失败 outcome=failed_retryable error=submission_suspended",
                module: .network
            )
            return .failedRetryable
        }

        if reason == .appLaunch, didSubmitAnonymousBootstrapThisLaunch {
            logger.info(
                "设备登记阶段跳过 outcome=skipped_same_launch_submission reason=\(reason.rawValue)",
                module: .network
            )
            return .skippedSameLaunchSubmission
        }

        if let accountID, isBootstrapRegistrationReason(reason), reason != .appLaunch {
            if bootstrapSubmittedAccountIDs.contains(accountID) {
                logger.info(
                    "设备登记阶段跳过 outcome=skipped_same_launch_submission accountID=\(accountID) reason=\(reason.rawValue)",
                    module: .network
                )
                return .skippedSameLaunchSubmission
            }
        }

        let resolvedAccountID = accountID ?? currentUserID()
        logger.info(
            "设备登记阶段开始 reason=\(reason.rawValue) accountID=\(resolvedAccountID.map(String.init) ?? "-")",
            module: .network
        )

        pendingReasons.insert(reason)
        rebuildPendingBaseSnapshot()

        let blockUntilFlush = isBootstrapRegistrationReason(reason)
        let outcome = await scheduleFlushAfterResolvingNotifications(
            apnsWaitWindowNs: bootstrapApnsWaitWindowNs,
            blockUntilFlush: blockUntilFlush,
            bootstrapAccountID: resolvedAccountID,
            forceSubmit: isBootstrapRegistrationReason(reason)
        )

        logger.info(
            "设备登记阶段完成 outcome=\(outcome.logLabel) reason=\(reason.rawValue) accountID=\(resolvedAccountID.map(String.init) ?? "-")",
            module: .network
        )
        return outcome
    }

    /// 引导级登记：失败后按固定次数与退避重试（APP-STARTUP-000010）。
    @discardableResult
    func requestRegisterWithLimitedRetry(
        reason: DeviceRegistrationReason,
        accountID: Int? = nil,
        maxAttempts: Int = DeviceRegistrationBootstrapRetryPolicy.maxAttempts
    ) async -> DeviceRegistrationRequestOutcome {
        guard isBootstrapRegistrationReason(reason) else {
            return await requestRegister(reason: reason, accountID: accountID)
        }

        let attempts = max(1, maxAttempts)
        var lastOutcome: DeviceRegistrationRequestOutcome = .failedRetryable

        for attemptIndex in 0 ..< attempts {
            let backoff = DeviceRegistrationBootstrapRetryPolicy.backoffBeforeAttempt(attemptIndex)
            if backoff > 0 {
                logger.info(
                    "设备登记重试 backoffMs=\(backoff / 1_000_000) attempt=\(attemptIndex + 1)/\(attempts)",
                    module: .network
                )
                try? await Task.sleep(nanoseconds: backoff)
            }

            lastOutcome = await requestRegister(reason: reason, accountID: accountID)
            switch lastOutcome {
            case .submitted, .skippedSameLaunchSubmission, .authSessionInvalidated:
                return lastOutcome
            case .failedRetryable:
                logger.warning(
                    "设备登记重试失败 attempt=\(attemptIndex + 1)/\(attempts) reason=\(reason.rawValue)",
                    module: .network
                )
            }
        }

        logger.warning(
            "设备登记重试已用尽 attempts=\(attempts) reason=\(reason.rawValue)",
            module: .network
        )
        return lastOutcome
    }

    /// 用户主动改变系统通知权限（设置页或应用内弹窗）。由协调器统一触发 APNs 注册。
    func updateNotificationAuthorization(granted: Bool) async {
        guard !isSubmissionSuspended else { return }
        pendingReasons.insert(.notificationAuthorization)
        rebuildPendingBaseSnapshot()

        if granted {
            if let hex = latestApnsTokenHex {
                pendingState?.notificationsEnabled = true
                pendingState?.pushToken = .value(hex)
                _ = await flushIfNeeded(forceSubmit: false)
                return
            }
            isAwaitingUserAuthorizationApnsToken = true
            pendingState?.notificationsEnabled = true
            pendingState?.pushToken = .unknown
            notificationEnvironment.registerForRemoteNotifications()
            return
        }

        cancelApnsWait()
        isAwaitingUserAuthorizationApnsToken = false
        pendingState?.notificationsEnabled = false
        pendingState?.pushToken = .cleared
        _ = await flushIfNeeded(forceSubmit: false)
    }

    /// APNs 注册失败（仅用户授权流程下的兜底一次上送）。
    func noteApnsRegistrationFailed() async {
        guard isAwaitingUserAuthorizationApnsToken else { return }
        isAwaitingUserAuthorizationApnsToken = false
        pendingState?.notificationsEnabled = false
        pendingState?.pushToken = .unknown
        _ = await flushIfNeeded(forceSubmit: false)
    }

    /// APNs device token 回调：仅更新状态；若已有等待中的聚合 flush 则不提前提交。
    func updateApnsToken(_ token: String) async {
        guard !isSubmissionSuspended else { return }
        latestApnsTokenHex = token
        pendingReasons.insert(.apnsTokenUpdate)
        ensurePendingSnapshot()
        pendingState?.pushToken = .value(token)
        pendingState?.notificationsEnabled = true

        if isAwaitingUserAuthorizationApnsToken {
            isAwaitingUserAuthorizationApnsToken = false
            _ = await flushIfNeeded(forceSubmit: false)
            return
        }

        if apnsWaitTask != nil {
            pendingState?.pushToken = .value(token)
            pendingState?.notificationsEnabled = true
            return
        }

        if shouldCompensatePushTokenSubmission(newToken: token) {
            _ = await flushIfNeeded(forceSubmit: false)
            return
        }

        if !hasUnsettledBootstrapIntent() {
            _ = await flushIfNeeded(forceSubmit: false)
        }
    }

    /// 应用回到前台：仅当通知授权或 token 相对持久化摘要有变化时才登记。
    func handleForegroundResume() async {
        guard !isSubmissionSuspended else { return }

        let status = await notificationEnvironment.authorizationStatus()
        let statusRaw = status.rawValue

        guard hasForegroundRegistrationDelta(statusRaw: statusRaw) else {
            logger.debug(
                "设备登记跳过：前台恢复且通知权限与 token 均未变化",
                module: .network
            )
            return
        }

        pendingReasons.insert(.foregroundPermissionCheck)
        rebuildPendingBaseSnapshot()
        applyNotificationFields(for: status)
        _ = await scheduleFlushAfterResolvingNotifications(
            apnsWaitWindowNs: bootstrapApnsWaitWindowNs,
            bootstrapAccountID: currentUserID(),
            forceSubmit: false
        )
    }

    // MARK: - Private

    private func isBootstrapRegistrationReason(_ reason: DeviceRegistrationReason) -> Bool {
        switch reason {
        case .appLaunch, .signedInBootstrap, .signedInColdLaunch:
            return true
        case .notificationAuthorization, .apnsTokenUpdate, .foregroundPermissionCheck:
            return false
        }
    }

    private func rebuildPendingBaseSnapshot() {
        let signedInAccountID = currentUserID()
        pendingState = DeviceRegistrationState.baseSnapshot(
            accountID: signedInAccountID ?? deviceCache.lastLoggedInAccountID,
            systemInfo: systemInfo
        )
        pendingState?.isAuthenticated = signedInAccountID != nil
    }

    private func ensurePendingSnapshot() {
        if pendingState == nil {
            rebuildPendingBaseSnapshot()
        }
    }

    private func hasUnsettledBootstrapIntent() -> Bool {
        pendingReasons.contains(.appLaunch)
            || pendingReasons.contains(.signedInBootstrap)
            || pendingReasons.contains(.signedInColdLaunch)
    }

    private var effectiveRegistrationAccountID: Int? {
        currentUserID() ?? deviceCache.lastLoggedInAccountID
    }

    private func hasForegroundRegistrationDelta(statusRaw: Int) -> Bool {
        let tokenHash = latestApnsTokenHex.map { DeviceRegistrationSubmittedSnapshot.hashPushToken(.value($0)) } ?? nil
        let snapshot = deviceCache.lastDeviceRegistrationSnapshot

        if let snapshot {
            let accountID = effectiveRegistrationAccountID
            if snapshot.accountID != accountID { return true }
            if snapshot.bundleID != systemInfo.bundleIdentifier { return true }
            if snapshot.deviceID != systemInfo.installationDeviceID { return true }
            if snapshot.authorizationStatusRaw != statusRaw { return true }
            if let persistedHash = snapshot.pushTokenHash {
                if tokenHash == nil {
                    return false
                }
                if persistedHash != tokenHash {
                    return true
                }
                return false
            }
            if tokenHash != nil {
                return true
            }
            return false
        }

        let lastSubmittedToken = lastSubmittedState.flatMap { submittedApnsTokenHex(from: $0.pushToken) }
        let authChanged = cachedAuthorizationStatusRaw != statusRaw
        let tokenChanged = latestApnsTokenHex != lastSubmittedToken
        return authChanged || tokenChanged
    }

    @discardableResult
    private func scheduleFlushAfterResolvingNotifications(
        apnsWaitWindowNs: UInt64,
        blockUntilFlush: Bool = false,
        bootstrapAccountID: Int? = nil,
        forceSubmit: Bool
    ) async -> DeviceRegistrationRequestOutcome {
        let status = await notificationEnvironment.authorizationStatus()
        applyNotificationFields(for: status)

        if Self.isAuthorizationGranted(status) {
            if latestApnsTokenHex != nil {
                pendingState?.pushToken = .value(latestApnsTokenHex!)
                pendingState?.notificationsEnabled = true
                return await flushIfNeeded(
                    forceSubmit: forceSubmit,
                    bootstrapAccountID: bootstrapAccountID
                )
            }
            notificationEnvironment.registerForRemoteNotifications()
            if blockUntilFlush {
                logger.info(
                    "设备登记等待 APNs token timeout=\(Double(apnsWaitWindowNs) / 1_000_000_000)s",
                    module: .network
                )
            }
            return await scheduleApnsWaitThenFlush(
                waitNs: apnsWaitWindowNs,
                allowFlushWithoutToken: true,
                blockUntilFlush: blockUntilFlush,
                bootstrapAccountID: bootstrapAccountID,
                forceSubmit: forceSubmit
            )
        }

        cancelApnsWait()
        return await flushIfNeeded(
            forceSubmit: forceSubmit,
            bootstrapAccountID: bootstrapAccountID
        )
    }

    private func applyNotificationFields(for status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral:
            pendingState?.notificationsEnabled = true
            if let hex = latestApnsTokenHex {
                pendingState?.pushToken = .value(hex)
            } else {
                pendingState?.pushToken = .unknown
            }
        case .denied:
            pendingState?.notificationsEnabled = false
            pendingState?.pushToken = .cleared
        case .notDetermined:
            pendingState?.notificationsEnabled = nil
            pendingState?.pushToken = .unknown
        @unknown default:
            pendingState?.notificationsEnabled = nil
            pendingState?.pushToken = .unknown
        }
    }

    @discardableResult
    private func scheduleApnsWaitThenFlush(
        waitNs: UInt64,
        allowFlushWithoutToken: Bool = true,
        blockUntilFlush: Bool = false,
        bootstrapAccountID: Int? = nil,
        forceSubmit: Bool
    ) async -> DeviceRegistrationRequestOutcome {
        cancelApnsWait()
        if blockUntilFlush {
            return await runApnsWaitThenFlush(
                waitNs: waitNs,
                allowFlushWithoutToken: allowFlushWithoutToken,
                bootstrapAccountID: bootstrapAccountID,
                forceSubmit: forceSubmit
            )
        }
        apnsWaitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.runApnsWaitThenFlush(
                waitNs: waitNs,
                allowFlushWithoutToken: allowFlushWithoutToken,
                bootstrapAccountID: bootstrapAccountID,
                forceSubmit: forceSubmit
            )
            self.apnsWaitTask = nil
        }
        return .submitted
    }

    private func runApnsWaitThenFlush(
        waitNs: UInt64,
        allowFlushWithoutToken: Bool,
        bootstrapAccountID: Int? = nil,
        forceSubmit: Bool
    ) async -> DeviceRegistrationRequestOutcome {
        try? await Task.sleep(nanoseconds: waitNs)
        guard !Task.isCancelled, !isSubmissionSuspended else { return .failedRetryable }
        if let hex = latestApnsTokenHex {
            pendingState?.pushToken = .value(hex)
            pendingState?.notificationsEnabled = true
            return await flushIfNeeded(
                forceSubmit: forceSubmit,
                bootstrapAccountID: bootstrapAccountID
            )
        }
        guard allowFlushWithoutToken else {
            logger.debug(
                "设备登记继续等待 APNs token，冷启动阶段不上送无 token 状态",
                module: .network
            )
            return .failedRetryable
        }
        pendingState?.notificationsEnabled = true
        pendingState?.pushToken = .unknown
        return await flushIfNeeded(
            forceSubmit: forceSubmit,
            bootstrapAccountID: bootstrapAccountID
        )
    }

    private func cancelApnsWait() {
        apnsWaitTask?.cancel()
        apnsWaitTask = nil
    }

    @discardableResult
    private func flushIfNeeded(
        forceSubmit: Bool,
        bootstrapAccountID: Int? = nil
    ) async -> DeviceRegistrationRequestOutcome {
        guard !isSubmissionSuspended else { return .failedRetryable }
        guard let state = pendingState else { return .failedRetryable }

        if forceSubmit == false, state == lastSubmittedState {
            let reasons = pendingReasons.map(\.rawValue).sorted().joined(separator: ", ")
            logger.info(
                "设备登记跳过：状态未变化 reasons=[\(reasons)]",
                module: .network
            )
            pendingReasons.removeAll()
            return .skippedSameLaunchSubmission
        }

        let reasons = pendingReasons.map(\.rawValue).sorted().joined(separator: ", ")
        let includesPushToken: Bool = {
            if case .value = state.pushToken { return true }
            return false
        }()
        logger.info(
            "设备登记提交 reasons=[\(reasons)] includesPushToken=\(includesPushToken)",
            module: .network
        )

        let registerOutcome = await registerDevice.execute(state: state)
        pendingReasons.removeAll()
        return await mapRegisterOutcome(
            registerOutcome,
            state: state,
            bootstrapAccountID: bootstrapAccountID
        )
    }

    private func mapRegisterOutcome(
        _ outcome: RegisterDeviceOutcome,
        state: DeviceRegistrationState,
        bootstrapAccountID: Int?
    ) async -> DeviceRegistrationRequestOutcome {
        switch outcome {
        case .succeeded:
            lastSubmittedState = state
            if let accountID = state.accountID {
                deviceCache.cacheLastLoggedInAccountID(accountID)
            }
            if state.isAuthenticated {
                let trackedID = bootstrapAccountID ?? state.accountID
                if let trackedID {
                    bootstrapSubmittedAccountIDs.insert(trackedID)
                }
            } else {
                didSubmitAnonymousBootstrapThisLaunch = true
            }
            let statusRaw = await notificationEnvironment.authorizationStatus().rawValue
            cachedAuthorizationStatusRaw = statusRaw
            let snapshot = DeviceRegistrationSubmittedSnapshot.from(
                state: state,
                authorizationStatusRaw: statusRaw
            )
            deviceCache.cacheDeviceRegistrationSnapshot(snapshot)
            return .submitted
        case .authSessionInvalidated:
            suspendPendingSubmissions()
            return .authSessionInvalidated
        case .failed, .skippedMissingAuthenticatedCredentials:
            logger.warning(
                "设备登记阶段失败 outcome=failed_retryable error=\(registerOutcomeLogLabel(outcome))",
                module: .network
            )
            return .failedRetryable
        }
    }

    private func registerOutcomeLogLabel(_ outcome: RegisterDeviceOutcome) -> String {
        switch outcome {
        case .succeeded:
            return "succeeded"
        case .failed:
            return "failed"
        case .skippedMissingAuthenticatedCredentials:
            return "skipped_missing_authenticated_credentials"
        case .authSessionInvalidated:
            return "auth_session_invalidated"
        }
    }

    private func submittedApnsTokenHex(from pushToken: PushTokenState) -> String? {
        if case let .value(hex) = pushToken { return hex }
        return nil
    }

    /// 基础登记已上送但尚无 token 时，token 晚到仅补偿一次（受 snapshot / 上次提交约束）。
    private func shouldCompensatePushTokenSubmission(newToken: String) -> Bool {
        let newHash = DeviceRegistrationSubmittedSnapshot.hashPushToken(.value(newToken))

        if let last = lastSubmittedState {
            let lastHadToken = submittedApnsTokenHex(from: last.pushToken) != nil
            if !lastHadToken {
                return true
            }
            if let lastHex = submittedApnsTokenHex(from: last.pushToken), lastHex != newToken {
                return true
            }
            return false
        }

        if let snapshot = deviceCache.lastDeviceRegistrationSnapshot {
            if snapshot.pushTokenHash == nil {
                return newHash != nil
            }
            if let persisted = snapshot.pushTokenHash, let newHash, persisted != newHash {
                return true
            }
        }
        return false
    }

    private static func isAuthorizationGranted(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}

private extension DeviceRegistrationRequestOutcome {
    var logLabel: String {
        switch self {
        case .submitted:
            return "submitted"
        case .skippedSameLaunchSubmission:
            return "skipped_same_launch_submission"
        case .failedRetryable:
            return "failed_retryable"
        case .authSessionInvalidated:
            return "auth_session_invalidated"
        }
    }
}
