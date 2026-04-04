import Foundation
import UIKit

@MainActor
final class SparkApplicationDelegate: NSObject, UIApplicationDelegate {
    static var bootstrapPushAdapter: PushAdapter?
    var pushAdapter: PushAdapter?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if pushAdapter == nil {
            pushAdapter = Self.bootstrapPushAdapter
        }
        pushAdapter?.installAsNotificationCenterDelegate()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushAdapter?.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushAdapter?.handleDeviceTokenRegistrationError(error)
    }
}
