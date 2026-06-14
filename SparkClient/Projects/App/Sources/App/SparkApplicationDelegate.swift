import Foundation
import UIKit

@MainActor
final class SparkApplicationDelegate: NSObject, UIApplicationDelegate {
    static var bootstrapPushAdapter: PushAdapter?
    static var bootstrapExternalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator?

    var pushAdapter: PushAdapter?
    var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if pushAdapter == nil {
            pushAdapter = Self.bootstrapPushAdapter
        }
        if externalMedicalDocumentImportCoordinator == nil {
            externalMedicalDocumentImportCoordinator = Self.bootstrapExternalMedicalDocumentImportCoordinator
        }
        pushAdapter?.installAsNotificationCenterDelegate()
        resolveCoordinator()?.consumeLaunchOptions(launchOptions)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        resolveCoordinator()?.consumeConnectionOptions(options)
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return resolveCoordinator()?.tryReceive(url, source: .applicationOpen) ?? false
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushAdapter?.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushAdapter?.handleDeviceTokenRegistrationError(error)
    }

    private func resolveCoordinator() -> ExternalMedicalDocumentImportCoordinator? {
        if externalMedicalDocumentImportCoordinator == nil {
            externalMedicalDocumentImportCoordinator = Self.bootstrapExternalMedicalDocumentImportCoordinator
        }
        return externalMedicalDocumentImportCoordinator
    }
}
