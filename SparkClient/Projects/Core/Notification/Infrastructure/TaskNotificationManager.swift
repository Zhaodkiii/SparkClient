import Foundation
import UserNotifications

enum TaskNotificationSchedulingState: Equatable, Sendable {
    case scheduled
    case waitingForCapacity
    case disabled
    case systemDenied
    case missingTime
    case past
}

@MainActor
final class TaskNotificationManager {
    static let shared = TaskNotificationManager()

    private let center: UNUserNotificationCenter
    private let logger: Logger
    private let capacity = 48
    private var accountID: Int64?
    private var states: [Int: TaskNotificationSchedulingState] = [:]

    init(center: UNUserNotificationCenter = .current(), logger: Logger = ConsoleLogger()) {
        self.center = center
        self.logger = logger
    }

    func configure(accountID: Int64) {
        let previous = self.accountID
        self.accountID = accountID
        guard let previous, previous != accountID else { return }
        let prefix = "task_\(previous)_"
        Task { @MainActor in
            let requests = await center.pendingNotificationRequests()
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        states.removeAll()
    }

    func clearCurrentAccount() async {
        guard let accountID else { return }
        let prefix = "task_\(accountID)_"
        let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        self.accountID = nil
        states.removeAll()
    }

    @discardableResult
    func registerTaskNotification(
        for task: HealthTask,
        requestPermissionIfNeeded: Bool = true
    ) async -> TaskNotificationSchedulingState {
        await removeNotification(for: task)
        guard task.notificationEnabled, task.status == .pending else {
            states[task.id] = .disabled
            return .disabled
        }
        guard let accountID else {
            logger.warning("任务提醒未注册：账号尚未配置 task_id=\(task.id)", module: .push)
            states[task.id] = .systemDenied
            return .systemDenied
        }
        guard let fireDate = effectiveFireDate(for: task) else {
            states[task.id] = .missingTime
            return .missingTime
        }
        if task.repeatType == .none, fireDate <= Date() {
            states[task.id] = .past
            return .past
        }
        guard await notificationsAllowed(requestIfNeeded: requestPermissionIfNeeded) else {
            states[task.id] = .systemDenied
            return .systemDenied
        }
        guard let trigger = makeTrigger(for: task, date: fireDate) else {
            states[task.id] = .missingTime
            return .missingTime
        }

        let identifier = notificationID(accountID: accountID, taskID: task.id)
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("task.notification.title", comment: "健康任务提醒")
        content.body = String(format: NSLocalizedString("task.notification.body", comment: "你有一个待完成任务：%@"), task.title)
        content.sound = .default
        content.userInfo = [
            "type": "task_reminder", "route": "task_detail", "account_id": accountID,
            "member_id": task.member, "task_id": task.id, "notification_id": identifier,
            "scheduled_at": ISO8601DateFormatter().string(from: fireDate),
        ]

        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            states[task.id] = .scheduled
            return .scheduled
        } catch {
            logger.error("任务提醒注册失败 task_id=\(task.id) error=\(error.localizedDescription)", module: .push)
            states[task.id] = .systemDenied
            return .systemDenied
        }
    }

    func updateTaskNotification(for task: HealthTask) async {
        _ = await registerTaskNotification(for: task)
    }

    func reconcile(tasks: [HealthTask], requestPermissionIfNeeded: Bool = false) async {
        guard let accountID else { return }
        let prefix = "task_\(accountID)_"
        let existing = await center.pendingNotificationRequests()
        let taskIDs = Set(tasks.map(\.id))
        let stale = existing.map(\.identifier).filter { identifier in
            guard identifier.hasPrefix(prefix), let id = Int(identifier.dropFirst(prefix.count)) else { return false }
            return taskIDs.contains(id) == false
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let candidates = tasks.compactMap { task -> (HealthTask, Date)? in
            guard task.notificationEnabled, task.status == .pending, let date = nextFireDate(for: task) else { return nil }
            return (task, date)
        }.sorted { $0.1 < $1.1 }
        let selectedIDs = Set(candidates.prefix(capacity).map { $0.0.id })

        for (task, _) in candidates {
            if selectedIDs.contains(task.id) {
                _ = await registerTaskNotification(for: task, requestPermissionIfNeeded: requestPermissionIfNeeded)
            } else {
                await removeNotification(for: task)
                states[task.id] = .waitingForCapacity
            }
        }
        for task in tasks where task.notificationEnabled == false || task.status != .pending {
            await removeNotification(for: task)
            states[task.id] = .disabled
        }
    }

    func removeNotification(for task: HealthTask) async {
        guard let accountID else { return }
        removeNotification(identifier: notificationID(accountID: accountID, taskID: task.id))
    }

    func removeNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func notificationID(for task: HealthTask) -> String {
        notificationID(accountID: accountID ?? 0, taskID: task.id)
    }

    func schedulingState(for task: HealthTask) async -> TaskNotificationSchedulingState {
        if let state = states[task.id] { return state }
        if task.notificationEnabled == false { return .disabled }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { return .systemDenied }
        guard let date = effectiveFireDate(for: task) else { return .missingTime }
        if task.repeatType == .none, date <= Date() { return .past }
        return .scheduled
    }

    private func notificationID(accountID: Int64, taskID: Int) -> String { "task_\(accountID)_\(taskID)" }

    private func effectiveFireDate(for task: HealthTask) -> Date? {
        task.taskMedical?.reminderTime ?? task.startTime ?? task.dueTime
    }

    private func nextFireDate(for task: HealthTask) -> Date? {
        guard let date = effectiveFireDate(for: task) else { return nil }
        if task.repeatType == .none { return date > Date() ? date : nil }
        let components: Set<Calendar.Component> = task.repeatType == .daily ? [.hour, .minute] : [.weekday, .hour, .minute]
        return Calendar.current.nextDate(after: Date(), matching: Calendar.current.dateComponents(components, from: date), matchingPolicy: .nextTime)
    }

    private func makeTrigger(for task: HealthTask, date: Date) -> UNNotificationTrigger? {
        let components: Set<Calendar.Component>
        switch task.repeatType {
        case .none: components = [.year, .month, .day, .hour, .minute]
        case .daily: components = [.hour, .minute]
        case .weekly: components = [.weekday, .hour, .minute]
        }
        return UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(components, from: date), repeats: task.repeatType != .none)
    }

    private func notificationsAllowed(requestIfNeeded: Bool) async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined where requestIfNeeded:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        default: return false
        }
    }
}
