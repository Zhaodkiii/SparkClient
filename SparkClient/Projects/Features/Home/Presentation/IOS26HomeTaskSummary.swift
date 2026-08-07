import Foundation

struct IOS26HomeTaskSummary: Equatable, Sendable {
    let pendingCount: Int
    let overdueCount: Int
    let todayCount: Int
    let lastSyncTime: Date?
    let items: [IOS26HomeTaskSummaryItem]
    let isLoading: Bool
    let errorMessage: String?
}

struct IOS26HomeTaskSummaryItem: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let subtitle: String
    let timeText: String
    let badgeText: String?
    let priority: HealthTask.Priority
    let status: HealthTask.TaskStatus
    let taskType: HealthTask.TaskType
}

enum IOS26HomeTaskSummaryBuilder {
    static func makeHomeTaskSummary(
        tasks: [HealthTask],
        lastSyncTime: Date?,
        isLoading: Bool,
        errorMessage: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> IOS26HomeTaskSummary {
        let pending = tasks.filter { $0.status == .pending }

        let overdueCount = pending.filter { isOverdue($0, now: now) }.count

        let todayCount = pending.filter { task in
            if let due = task.dueTime {
                return calendar.isDateInToday(due)
            }
            if let start = task.startTime {
                return calendar.isDateInToday(start)
            }
            return false
        }.count

        let sorted = pending.sorted { lhs, rhs in
            let lhsOverdue = isOverdue(lhs, now: now)
            let rhsOverdue = isOverdue(rhs, now: now)
            if lhsOverdue != rhsOverdue {
                return lhsOverdue
            }
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }
            let leftDate = lhs.dueTime ?? lhs.startTime ?? lhs.updatedAt
            let rightDate = rhs.dueTime ?? rhs.startTime ?? rhs.updatedAt
            return leftDate < rightDate
        }

        let items = sorted.prefix(3).map { task in
            IOS26HomeTaskSummaryItem(
                id: task.id,
                title: task.title,
                subtitle: task.description.isEmpty ? task.type.displayName : task.description,
                timeText: formatTaskTime(task),
                badgeText: task.priority == .high ? L10n.text("ios26.home.tasks.badge.high_priority") : nil,
                priority: task.priority,
                status: task.status,
                taskType: task.type
            )
        }

        return IOS26HomeTaskSummary(
            pendingCount: pending.count,
            overdueCount: overdueCount,
            todayCount: todayCount,
            lastSyncTime: lastSyncTime,
            items: Array(items),
            isLoading: isLoading,
            errorMessage: errorMessage
        )
    }

    private static func isOverdue(_ task: HealthTask, now: Date) -> Bool {
        guard let due = task.dueTime else { return false }
        return due < now
    }

    private static func formatTaskTime(_ task: HealthTask) -> String {
        if let due = task.dueTime {
            return DateFormatter.localizedString(from: due, dateStyle: .none, timeStyle: .short)
        }
        if let start = task.startTime {
            return DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)
        }
        return L10n.text("task.time.unspecified")
    }
}
