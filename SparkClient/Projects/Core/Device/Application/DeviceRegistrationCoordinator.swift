import Foundation
import UIKit
import UserNotifications

/// 设备登记触发来源（用于日志区分与聚合）。
enum DeviceRegistrationReason: String, Sendable {
    case appLaunch = "app_launch"
    case signedInBootstrap = "signed_in_bootstrap"
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

/// 设备信息上送：事件源只更新统一状态，由协调器聚合后最多提交一次完整登记。
@MainActor
final class DeviceRegistrationCoordinator {
    private let registerDevice: RegisterDeviceUseCase
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

    private var authInvalidationObserver: NSObjectProtocol?

    /// 冷启动/登录引导等待 APNs token（纳秒）。
    private let bootstrapApnsWaitWindowNs: UInt64 = 1_500_000_000

    init(
        registerDevice: RegisterDeviceUseCase,
        deviceCache: DeviceCache,
        currentUserID: @escaping () -> Int? = { nil },
        systemInfo: SparkSystemInfo? = nil,
        notificationEnvironment: (any DeviceNotificationEnvironment)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.registerDevice = registerDevice
        self.deviceCache = deviceCache
        self.currentUserID = currentUserID
        self.systemInfo = systemInfo ?? SparkSystemInfo()
        self.notificationEnvironment = notificationEnvironment ?? SystemDeviceNotificationEnvironment()
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
        deviceCache.clearDeviceRegistrationSnapshot()
    }

    func suspendPendingSubmissions() {
        isSubmissionSuspended = true
        cancelApnsWait()
        isAwaitingUserAuthorizationApnsToken = false
        pendingReasons.removeAll()
        logger.info("设备登记已暂停：鉴权失效处理中", module: .network)
    }

    /// App 冷启动（未登录）或登录后账号引导：写入意图并由协调器统一 flush（含 APNs 短等待）。
    func requestRegister(reason: DeviceRegistrationReason) async {
        guard !isSubmissionSuspended else { return }
        pendingReasons.insert(reason)
        rebuildPendingBaseSnapshot()
        await scheduleFlushAfterResolvingNotifications(apnsWaitWindowNs: bootstrapApnsWaitWindowNs)
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
                await flushIfNeeded()
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
        await flushIfNeeded()
    }

    /// APNs 注册失败（仅用户授权流程下的兜底一次上送）。
    func noteApnsRegistrationFailed() async {
        guard isAwaitingUserAuthorizationApnsToken else { return }
        isAwaitingUserAuthorizationApnsToken = false
        pendingState?.notificationsEnabled = false
        pendingState?.pushToken = .unknown
        await flushIfNeeded()
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
            await flushIfNeeded()
            return
        }

        if apnsWaitTask != nil {
            pendingState?.pushToken = .value(token)
            pendingState?.notificationsEnabled = true
            return
        }

        if shouldCompensatePushTokenSubmission(newToken: token) {
            await flushIfNeeded()
            return
        }

        if !hasUnsettledBootstrapIntent() {
            await flushIfNeeded()
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
        await scheduleFlushAfterResolvingNotifications(apnsWaitWindowNs: bootstrapApnsWaitWindowNs)
    }

    // MARK: - Private

    private func rebuildPendingBaseSnapshot() {
        pendingState = DeviceRegistrationState.baseSnapshot(
            accountID: currentUserID(),
            systemInfo: systemInfo
        )
    }

    private func ensurePendingSnapshot() {
        if pendingState == nil {
            rebuildPendingBaseSnapshot()
        }
    }

    private func hasUnsettledBootstrapIntent() -> Bool {
        pendingReasons.contains(.appLaunch) || pendingReasons.contains(.signedInBootstrap)
    }

    private func hasForegroundRegistrationDelta(statusRaw: Int) -> Bool {
        let tokenHash = latestApnsTokenHex.map { DeviceRegistrationSubmittedSnapshot.hashPushToken(.value($0)) } ?? nil
        let snapshot = deviceCache.lastDeviceRegistrationSnapshot

        if let snapshot {
            let accountID = currentUserID()
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

    private func scheduleFlushAfterResolvingNotifications(apnsWaitWindowNs: UInt64) async {
        let status = await notificationEnvironment.authorizationStatus()
        applyNotificationFields(for: status)

        if Self.isAuthorizationGranted(status) {
            if latestApnsTokenHex != nil {
                pendingState?.pushToken = .value(latestApnsTokenHex!)
                pendingState?.notificationsEnabled = true
                await flushIfNeeded()
                return
            }
            notificationEnvironment.registerForRemoteNotifications()
            await scheduleApnsWaitThenFlush(
                waitNs: apnsWaitWindowNs,
                allowFlushWithoutToken: true
            )
            return
        }

        cancelApnsWait()
        await flushIfNeeded()
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

    private func scheduleApnsWaitThenFlush(waitNs: UInt64, allowFlushWithoutToken: Bool = true) async {
        cancelApnsWait()
        apnsWaitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: waitNs)
            guard !Task.isCancelled, !self.isSubmissionSuspended else { return }
            self.apnsWaitTask = nil
            if let hex = self.latestApnsTokenHex {
                self.pendingState?.pushToken = .value(hex)
                self.pendingState?.notificationsEnabled = true
                await self.flushIfNeeded()
                return
            }
            guard allowFlushWithoutToken else {
                self.logger.debug(
                    "设备登记继续等待 APNs token，冷启动阶段不上送无 token 状态",
                    module: .network
                )
                return
            }
            self.pendingState?.notificationsEnabled = true
            self.pendingState?.pushToken = .unknown
            await self.flushIfNeeded()
        }
    }

    private func cancelApnsWait() {
        apnsWaitTask?.cancel()
        apnsWaitTask = nil
    }

    private func flushIfNeeded() async {
        guard !isSubmissionSuspended else { return }
        guard let state = pendingState else { return }

        if state == lastSubmittedState {
            let reasons = pendingReasons.map(\.rawValue).sorted().joined(separator: ", ")
            logger.info(
                "设备登记跳过：状态未变化 reasons=[\(reasons)]",
                module: .network
            )
            pendingReasons.removeAll()
            return
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

        let outcome = await registerDevice.execute(state: state)
        switch outcome {
        case .succeeded:
            lastSubmittedState = state
            let statusRaw = await notificationEnvironment.authorizationStatus().rawValue
            cachedAuthorizationStatusRaw = statusRaw
            let snapshot = DeviceRegistrationSubmittedSnapshot.from(
                state: state,
                authorizationStatusRaw: statusRaw
            )
            deviceCache.cacheDeviceRegistrationSnapshot(snapshot)
        case .authSessionInvalidated:
            suspendPendingSubmissions()
        case .failed, .skippedMissingAuthenticatedCredentials:
            break
        }
        pendingReasons.removeAll()
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
