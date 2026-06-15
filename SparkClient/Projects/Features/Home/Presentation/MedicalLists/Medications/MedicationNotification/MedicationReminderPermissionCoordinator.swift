import Foundation
import UserNotifications

enum MedicationReminderPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case provisional
    case ephemeral
    case denied
}

@MainActor
final class MedicationReminderPermissionCoordinator {
    private let center: UNUserNotificationCenter
    private let logger: Logger

    init(center: UNUserNotificationCenter = .current(), logger: Logger = ConsoleLogger()) {
        self.center = center
        self.logger = logger
    }

    func currentStatus() async -> MedicationReminderPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    var canScheduleNotifications: Bool {
        get async {
            switch await currentStatus() {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined, .denied:
                return false
            }
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        switch await currentStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                logger.info("用药提醒请求系统通知权限 granted=\(granted)", module: .push)
                return granted
            } catch {
                logger.warning("用药提醒请求系统通知权限失败 error=\(error.localizedDescription)", module: .push)
                return false
            }
        }
    }

    func openSystemSettings() {
#if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
