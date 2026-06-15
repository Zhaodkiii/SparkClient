import Foundation
import UIKit
import UserNotifications

@MainActor
protocol RemoteNotificationCenterClient: AnyObject {
    func install(delegate: UNUserNotificationCenterDelegate)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

@MainActor
final class SystemRemoteNotificationCenterClient: RemoteNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func install(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }
}

@MainActor
final class PushAdapter: NSObject, UNUserNotificationCenterDelegate {
    private let notificationCenter: any RemoteNotificationCenterClient
    private let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    private let logger: Logger
    private let onApnsTokenHex: (@Sendable (String) async -> Void)?
    /// 系统通知权限结果（与 APNs token 解耦）：拒绝或失败时用于同步 `TrustedDevice.notifications_enabled` / 清空 `push_token`。
    private let onRemoteNotificationAuthorizationResolved: (@Sendable (_ granted: Bool) async -> Void)?
    private let onApnsRegistrationFailed: (@Sendable () async -> Void)?

    init(
        handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase,
        notificationCenter: any RemoteNotificationCenterClient,
        logger: Logger = ConsoleLogger(),
        onApnsTokenHex: (@Sendable (String) async -> Void)? = nil,
        onRemoteNotificationAuthorizationResolved: (@Sendable (_ granted: Bool) async -> Void)? = nil,
        onApnsRegistrationFailed: (@Sendable () async -> Void)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.handleRemoteNotificationUseCase = handleRemoteNotificationUseCase
        self.logger = logger
        self.onApnsTokenHex = onApnsTokenHex
        self.onRemoteNotificationAuthorizationResolved = onRemoteNotificationAuthorizationResolved
        self.onApnsRegistrationFailed = onApnsRegistrationFailed
    }

    func installAsNotificationCenterDelegate() {
        notificationCenter.install(delegate: self)
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            await requestRemoteNotificationAuthorizationAndRegister()
        }
    }

    /// 仅在系统通知权限尚未决定时弹出权限对话框并注册 APNs。
    func requestAuthorizationIfNotDetermined() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            await requestRemoteNotificationAuthorizationAndRegister()
        }
    }

    /// 请求系统通知权限；授权结果交给 `DeviceRegistrationCoordinator`，由协调器触发 APNs 注册与聚合上送。
    private func requestRemoteNotificationAuthorizationAndRegister() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("业务=远程推送 请求系统通知权限 granted=\(granted)", module: .push)
            if granted {
                logger.info("业务=远程推送 权限已授予，交由设备登记协调器触发 APNs 注册", module: .push)
                await onRemoteNotificationAuthorizationResolved?(true)
            } else {
                logger.info("业务=远程推送 用户拒绝通知权限，同步后端关闭推送", module: .push)
                await onRemoteNotificationAuthorizationResolved?(false)
            }
        } catch {
            logger.warning("业务=远程推送 请求系统通知权限失败 error=\(error.localizedDescription)", module: .push)
            await onRemoteNotificationAuthorizationResolved?(false)
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("业务=远程推送 收到 APNs device token 待上报 byteLen=\(tokenData.count)", module: .push)
        guard let onApnsTokenHex else { return }
        Task {
            await onApnsTokenHex(hex)
        }
    }

    func handleDeviceTokenRegistrationError(_ error: Error) {
        logger.warning("业务=远程推送 向 APNs 注册 device token 失败（将无法收推送）error=\(error.localizedDescription)", module: .push)
        guard let onApnsRegistrationFailed else { return }
        Task {
            await onApnsRegistrationFailed()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let payload = RemoteNotificationPayload.from(
            userInfo: content.userInfo,
            fallbackTitle: content.title,
            fallbackBody: content.body
        )
        handleRemoteNotificationUseCase.execute(payload: payload, entryPoint: .foreground)

        // 前台统一走应用内通知系统，避免系统 banner 与应用内提示重复。
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let payload = RemoteNotificationPayload.from(
            userInfo: content.userInfo,
            fallbackTitle: content.title,
            fallbackBody: content.body
        )
        handleRemoteNotificationUseCase.execute(
            payload: payload,
            entryPoint: .interaction(actionIdentifier: response.actionIdentifier),
            notificationRequestID: response.notification.request.identifier
        )
        completionHandler()
    }
}
