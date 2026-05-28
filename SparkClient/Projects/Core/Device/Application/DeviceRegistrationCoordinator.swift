import Foundation

/// 设备登记触发来源（用于日志区分）。
enum DeviceRegistrationReason: String, Sendable {
    case appLaunch = "app_launch"
    case signedInBootstrap = "signed_in_bootstrap"
    case notificationAuthorization = "notification_authorization"
    case apnsTokenUpdate = "apns_token_update"
}

/// 合并通知权限与 APNs token 上报，避免同一次授权产生多次全量设备登记。
@MainActor
final class DeviceRegistrationCoordinator {
    private enum PushTokenField: Equatable {
        case omit
        case clear
        case value(String)
    }

    private struct SubmissionFingerprint: Equatable {
        let userID: Int?
        let pushToken: PushTokenField
        let notificationsEnabled: Bool?
        let regionCode: String
        let countryCode: String
    }

    private let registerDevice: RegisterDeviceUseCase
    private let currentUserID: () -> Int?
    private let systemInfo: SparkSystemInfo
    private let logger: Logger

    private var lastSubmitted: SubmissionFingerprint?
    private var awaitingApnsAfterAuthorization = false
    private var apnsMergeTask: Task<Void, Never>?

    /// 授权成功后等待 APNs token 的合并窗口（纳秒）。
    private let apnsMergeWindowNs: UInt64 = 1_500_000_000
    /// 非紧急登记的短防抖，合并启动与登录引导等连续事件（纳秒）。
    private let debounceIntervalNs: UInt64 = 300_000_000
    private var debounceTask: Task<Void, Never>?

    init(
        registerDevice: RegisterDeviceUseCase,
        currentUserID: @escaping () -> Int? = { nil },
        systemInfo: SparkSystemInfo = SparkSystemInfo(),
        logger: Logger = ConsoleLogger()
    ) {
        self.registerDevice = registerDevice
        self.currentUserID = currentUserID
        self.systemInfo = systemInfo
        self.logger = logger
    }

    func reset() {
        lastSubmitted = nil
        awaitingApnsAfterAuthorization = false
        apnsMergeTask?.cancel()
        apnsMergeTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// App 冷启动或登录后账号引导的设备画像上送。
    func requestRegister(reason: DeviceRegistrationReason) async {
        cancelApnsMerge()
        await submit(
            pushToken: .omit,
            notificationsEnabled: nil,
            reason: reason,
            policy: reason == .signedInBootstrap ? .immediate : .debounced
        )
    }

    /// 系统通知权限结果（与 APNs token 解耦）。
    func updateNotificationAuthorization(granted: Bool) async {
        if granted {
            awaitingApnsAfterAuthorization = true
            apnsMergeTask?.cancel()
            apnsMergeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.apnsMergeWindowNs)
                guard !Task.isCancelled, self.awaitingApnsAfterAuthorization else { return }
                self.awaitingApnsAfterAuthorization = false
                await self.submit(
                    pushToken: .omit,
                    notificationsEnabled: true,
                    reason: .notificationAuthorization,
                    policy: .immediate
                )
            }
            return
        }

        cancelApnsMerge()
        await submit(
            pushToken: .clear,
            notificationsEnabled: false,
            reason: .notificationAuthorization,
            policy: .immediate
        )
    }

    /// APNs device token 回调。
    func updateApnsToken(_ token: String) async {
        let policy: SubmissionPolicy
        if awaitingApnsAfterAuthorization {
            awaitingApnsAfterAuthorization = false
            apnsMergeTask?.cancel()
            apnsMergeTask = nil
            policy = .immediate
        } else {
            policy = .debounced
        }

        await submit(
            pushToken: .value(token),
            notificationsEnabled: true,
            reason: .apnsTokenUpdate,
            policy: policy
        )
    }

    // MARK: - Private

    private enum SubmissionPolicy {
        case immediate
        case debounced
    }

    private func cancelApnsMerge() {
        awaitingApnsAfterAuthorization = false
        apnsMergeTask?.cancel()
        apnsMergeTask = nil
    }

    private func submit(
        pushToken: PushTokenField,
        notificationsEnabled: Bool?,
        reason: DeviceRegistrationReason,
        policy: SubmissionPolicy
    ) async {
        switch policy {
        case .immediate:
            debounceTask?.cancel()
            debounceTask = nil
            await performSubmit(pushToken: pushToken, notificationsEnabled: notificationsEnabled, reason: reason)
        case .debounced:
            debounceTask?.cancel()
            debounceTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.debounceIntervalNs)
                guard !Task.isCancelled else { return }
                await self.performSubmit(
                    pushToken: pushToken,
                    notificationsEnabled: notificationsEnabled,
                    reason: reason
                )
            }
        }
    }

    private func performSubmit(
        pushToken: PushTokenField,
        notificationsEnabled: Bool?,
        reason: DeviceRegistrationReason
    ) async {
        let fingerprint = SubmissionFingerprint(
            userID: currentUserID(),
            pushToken: pushToken,
            notificationsEnabled: notificationsEnabled,
            regionCode: systemInfo.regionCode,
            countryCode: systemInfo.mostLikelyCountryCode
        )

        if fingerprint == lastSubmitted {
            logger.info(
                "设备登记跳过：状态未变化 reason=\(reason.rawValue)",
                module: .network
            )
            return
        }

        let pushTokenParam: String?
        switch pushToken {
        case .omit:
            pushTokenParam = nil
        case .clear:
            pushTokenParam = ""
        case let .value(token):
            pushTokenParam = token
        }

        logger.info("设备登记提交 reason=\(reason.rawValue)", module: .network)
        let succeeded = await registerDevice.execute(
            pushToken: pushTokenParam,
            notificationsEnabled: notificationsEnabled
        )
        if succeeded {
            lastSubmitted = fingerprint
        }
    }
}
