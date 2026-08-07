import Foundation

enum TaskSorters {
    /// 过期优先 → 优先级 → 截止时间 → 更新时间
    static func makeVisibleTasks(
        tasks: [HealthTask],
        filters: TaskFilterSelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HealthTask] {
        filters
            .apply(to: tasks, now: now, calendar: calendar)
            .sorted { lhs, rhs in
                compare(lhs, rhs, now: now)
            }
    }

    static func compare(_ lhs: HealthTask, _ rhs: HealthTask, now: Date) -> Bool {
        let lhsOverdue = TaskDateHelper.isOverdue(lhs, now: now)
        let rhsOverdue = TaskDateHelper.isOverdue(rhs, now: now)
        if lhsOverdue != rhsOverdue { return lhsOverdue }

        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue < rhs.priority.rawValue
        }

        let leftDate = lhs.dueTime ?? lhs.startTime ?? lhs.updatedAt
        let rightDate = rhs.dueTime ?? rhs.startTime ?? rhs.updatedAt
        if leftDate != rightDate { return leftDate < rightDate }

        return lhs.updatedAt > rhs.updatedAt
    }
}

struct TaskListOverview: Equatable, Sendable {
    let pendingCount: Int
    let overdueCount: Int
    let todayCount: Int

    static func build(from tasks: [HealthTask], now: Date = Date(), calendar: Calendar = .current) -> TaskListOverview {
        let pending = tasks.filter { $0.status == .pending }
        let overdueCount = pending.filter { TaskDateHelper.isOverdue($0, now: now) }.count
        let todayCount = pending.filter { task in
            if let due = task.dueTime { return calendar.isDateInToday(due) }
            if let start = task.startTime { return calendar.isDateInToday(start) }
            return false
        }.count
        return TaskListOverview(
            pendingCount: pending.count,
            overdueCount: overdueCount,
            todayCount: todayCount
        )
    }
}
