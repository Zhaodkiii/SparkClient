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

    init(
        handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase,
        notificationCenter: any RemoteNotificationCenterClient,
        logger: Logger = ConsoleLogger(),
        onApnsTokenHex: (@Sendable (String) async -> Void)? = nil,
        onRemoteNotificationAuthorizationResolved: (@Sendable (_ granted: Bool) async -> Void)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.handleRemoteNotificationUseCase = handleRemoteNotificationUseCase
        self.logger = logger
        self.onApnsTokenHex = onApnsTokenHex
        self.onRemoteNotificationAuthorizationResolved = onRemoteNotificationAuthorizationResolved
    }

    func installAsNotificationCenterDelegate() {
        notificationCenter.install(delegate: self)
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            await requestRemoteNotificationAuthorizationAndRegister()
        }
    }

    /// 请求系统通知权限；同意则向 APNs 注册（token 在 `handleDeviceToken` 中上送），拒绝则同步后端关闭推送并清空 token。
    private func requestRemoteNotificationAuthorizationAndRegister() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("业务=远程推送 请求系统通知权限 granted=\(granted)", module: .push)
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                logger.info("业务=远程推送 已调用 registerForRemoteNotifications，等待 APNs token 回调", module: .push)
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
            entryPoint: .interaction(actionIdentifier: response.actionIdentifier)
        )
        completionHandler()
    }
}
