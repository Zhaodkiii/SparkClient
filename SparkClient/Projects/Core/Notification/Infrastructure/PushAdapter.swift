import Foundation
import UserNotifications

@MainActor
final class PushAdapter: NSObject, UNUserNotificationCenterDelegate {
    private let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    private let logger: Logger

    init(
        handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.handleRemoteNotificationUseCase = handleRemoteNotificationUseCase
        self.logger = logger
    }

    func installAsNotificationCenterDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                logger.info("Push authorization result: \(granted)", category: "notification")
            } catch {
                logger.warning("Push authorization failed: \(error.localizedDescription)", category: "notification")
            }
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs token received: \(token)", category: "notification")
    }

    func handleDeviceTokenRegistrationError(_ error: Error) {
        logger.warning("APNs token registration failed: \(error.localizedDescription)", category: "notification")
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
