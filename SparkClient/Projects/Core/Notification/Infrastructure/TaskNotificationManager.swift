import Foundation
import UserNotifications

@MainActor
final class TaskNotificationManager {
    static let shared = TaskNotificationManager()

    private let center: UNUserNotificationCenter
    private let logger: Logger

    init(center: UNUserNotificationCenter = .current(), logger: Logger = ConsoleLogger()) {
        self.center = center
        self.logger = logger
    }

    func registerTaskNotification(for task: HealthTask) async {
        let identifier = notificationID(for: task)
        await removeNotification(identifier: identifier)

        guard let trigger = makeTrigger(for: task) else {
            logger.warning("任务提醒未注册：缺少可用时间 task_id=\(task.id)", module: .push)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("task.notification.title", comment: "健康任务提醒")
        content.body = String(
            format: NSLocalizedString("task.notification.body", comment: "你有一个待完成任务：%@"),
            task.title
        )
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            logger.info("任务提醒注册成功 task_id=\(task.id) notification_id=\(identifier)", module: .push)
        } catch {
            logger.error("任务提醒注册失败 task_id=\(task.id) error=\(error.localizedDescription)", module: .push)
        }
    }

    func updateTaskNotification(for task: HealthTask) async {
        await registerTaskNotification(for: task)
    }

    func removeNotification(for task: HealthTask) async {
        await removeNotification(identifier: notificationID(for: task))
    }

    func removeNotification(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        logger.debug("任务提醒已移除 notification_id=\(identifier)", module: .push)
    }

    func notificationID(for task: HealthTask) -> String {
        if task.notificationID.isEmpty == false {
            return task.notificationID
        }
        return "task_\(task.id)"
    }

    private func makeTrigger(for task: HealthTask) -> UNNotificationTrigger? {
        let date = task.taskMedical?.reminderTime ?? task.startTime ?? task.dueTime
        guard let date else { return nil }

        let calendar = Calendar.current
        let components: Set<Calendar.Component>

        switch task.repeatType {
        case .none:
            components = [.year, .month, .day, .hour, .minute]
        case .daily:
            components = [.hour, .minute]
        case .weekly:
            components = [.weekday, .hour, .minute]
        }

        let dateComponents = calendar.dateComponents(components, from: date)
        let repeats = task.repeatType != .none
        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
    }
}
