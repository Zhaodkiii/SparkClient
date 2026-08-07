import Foundation

// MARK: - 筛选条件

enum TaskStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pending
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("common.all", comment: "All")
        case .pending:
            return NSLocalizedString("task.filter.pending", comment: "待完成")
        case .completed:
            return NSLocalizedString("task.filter.completed", comment: "已完成")
        }
    }

    func matches(_ status: HealthTask.TaskStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .pending:
            return status == .pending
        case .completed:
            return status == .completed
        }
    }
}

enum TaskTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case medical
    case exercise
    case diet

    var id: String { rawValue }

    var taskType: HealthTask.TaskType {
        switch self {
        case .medical: return .medical
        case .exercise: return .exercise
        case .diet: return .diet
        }
    }

    var title: String {
        taskType.displayName
    }

    func matches(_ type: HealthTask.TaskType) -> Bool {
        taskType == type
    }
}

enum TaskPriorityFilter: String, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var priority: HealthTask.Priority {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

    var title: String {
        priority.displayName
    }

    func matches(_ priority: HealthTask.Priority) -> Bool {
        self.priority == priority
    }
}

enum TaskTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case today
    case tomorrow
    case future

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return NSLocalizedString("task.filter.time.today", comment: "今日")
        case .tomorrow:
            return NSLocalizedString("task.filter.time.tomorrow", comment: "明日")
        case .future:
            return NSLocalizedString("task.filter.time.future", comment: "未来")
        }
    }

    func matches(_ task: HealthTask, now: Date, calendar: Calendar) -> Bool {
        let anchor = task.dueTime ?? task.startTime
        guard let anchor else { return false }
        switch self {
        case .today:
            return calendar.isDateInToday(anchor)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
            return calendar.isDate(anchor, inSameDayAs: tomorrow)
        case .future:
            if calendar.isDateInToday(anchor) { return false }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(anchor, inSameDayAs: tomorrow) {
                return false
            }
            return anchor > now
        }
    }
}

struct TaskFilterSelection: Equatable, Sendable {
    var status: TaskStatusFilter = .all
    var type: TaskTypeFilter?
    var priority: TaskPriorityFilter?
    var time: TaskTimeFilter?

    func apply(
        to tasks: [HealthTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HealthTask] {
        tasks.filter { task in
            status.matches(task.status)
                && (type?.matches(task.type) ?? true)
                && (priority?.matches(task.priority) ?? true)
                && (time?.matches(task, now: now, calendar: calendar) ?? true)
        }
    }
}

// MARK: - 任务辅助判断

enum TaskDateHelper {
    static func isOverdue(_ task: HealthTask, now: Date = Date()) -> Bool {
        guard task.status == .pending else { return false }
        let anchor = task.dueTime ?? task.startTime ?? .distantFuture
        return anchor < now
    }

    static func formatTaskTime(_ task: HealthTask) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if let due = task.dueTime {
            return formatter.string(from: due)
        }
        if let start = task.startTime {
            return formatter.string(from: start)
        }
        return NSLocalizedString("task.time.unspecified", comment: "未设置时间")
    }

    static func relativeTimeLabel(_ task: HealthTask, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let anchor = task.dueTime ?? task.startTime else {
            return NSLocalizedString("task.time.unspecified", comment: "未设置时间")
        }
        if calendar.isDateInToday(anchor) {
            let time = DateFormatter.localizedString(from: anchor, dateStyle: .none, timeStyle: .short)
            return String(format: NSLocalizedString("task.time.today_at", comment: "今天 %@"), time)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(anchor, inSameDayAs: tomorrow) {
            let time = DateFormatter.localizedString(from: anchor, dateStyle: .none, timeStyle: .short)
            return String(format: NSLocalizedString("task.time.tomorrow_at", comment: "明天 %@"), time)
        }
        return formatTaskTime(task)
    }
}

extension HealthTask.Priority {
    var displayName: String {
        switch self {
        case .high:
            return NSLocalizedString("task.priority.high", comment: "高优先级")
        case .medium:
            return NSLocalizedString("task.priority.medium", comment: "中优先级")
        case .low:
            return NSLocalizedString("task.priority.low", comment: "低优先级")
        }
    }
}

extension HealthTask.RepeatType {
    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("task.repeat.none", comment: "不重复")
        case .daily:
            return NSLocalizedString("task.repeat.daily", comment: "每日")
        case .weekly:
            return NSLocalizedString("task.repeat.weekly", comment: "每周")
        }
    }
}

extension HealthTask.Source {
    var displayName: String {
        switch self {
        case .manual:
            return NSLocalizedString("task.source.manual", comment: "手动创建")
        case .ai:
            return NSLocalizedString("task.source.ai", comment: "AI 生成")
        case .report:
            return NSLocalizedString("task.source.report", comment: "报告")
        }
    }
}
