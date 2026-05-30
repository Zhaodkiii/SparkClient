import Foundation

// MARK: - 任务主模型

struct HealthTask: Identifiable, Codable, Equatable, Sendable {
    enum TaskType: Int, Codable, CaseIterable, Sendable {
        case medical = 0
        case exercise = 1
        case diet = 2

        var displayName: String {
            switch self {
            case .medical: return NSLocalizedString("task.type.medical", comment: "医疗")
            case .exercise: return NSLocalizedString("task.type.exercise", comment: "运动")
            case .diet: return NSLocalizedString("task.type.diet", comment: "饮食")
            }
        }
    }

    enum TaskStatus: Int, Codable, CaseIterable, Sendable {
        case pending = 0
        case completed = 1
        case canceled = 2

        var displayName: String {
            switch self {
            case .pending: return NSLocalizedString("task.status.pending", comment: "待完成")
            case .completed: return NSLocalizedString("task.status.completed", comment: "已完成")
            case .canceled: return NSLocalizedString("task.status.canceled", comment: "已取消")
            }
        }
    }

    enum RepeatType: Int, Codable, Sendable {
        case none = 0
        case daily = 1
        case weekly = 2
    }

    enum Priority: Int, Codable, Sendable {
        case high = 0
        case medium = 1
        case low = 2
    }

    enum Source: Int, Codable, Sendable {
        case manual = 0
        case ai = 1
        case report = 2
    }

    enum LocalState: String, Codable, Sendable {
        case synced
        case creating
        case updating
        case deleting
        case failed
    }

    let id: Int
    let member: Int
    let creator: Int?
    var title: String
    var description: String
    var type: TaskType
    var status: TaskStatus
    var startTime: Date?
    var dueTime: Date?
    var repeatType: RepeatType
    var priority: Priority
    var businessType: String
    var businessId: String
    var source: Source
    var notificationId: String
    var extra: [String: String]
    var createdAt: Date
    var updatedAt: Date

    var taskMedical: TaskMedical?
    var taskExercise: TaskExercise?
    var taskDiet: TaskDiet?

    // 本地扩展字段
    var localState: LocalState?

    var businessID: String {
        get { businessId }
        set { businessId = newValue }
    }

    var notificationID: String {
        get { notificationId }
        set { notificationId = newValue }
    }
}

struct TaskMedical: Codable, Equatable, Sendable {
    let id: Int
    var status: HealthTask.TaskStatus
    var reminderTime: Date?
    var medicalTaskType: String
    var description: String
    var source: String
    var extra: [String: String]

}

struct TaskExercise: Codable, Equatable, Sendable {
    let id: Int
    var status: HealthTask.TaskStatus
    var exerciseType: String
    var durationMin: Int
    var intensity: String
    var description: String
    var source: String
    var extra: [String: String]

}

struct TaskDiet: Codable, Equatable, Sendable {
    let id: Int
    var status: HealthTask.TaskStatus
    var mealType: String
    var calorieTarget: Int
    var foodRecommend: [String]
    var description: String
    var source: String
    var extra: [String: String]

}

struct TaskStatusSyncItem: Codable, Sendable {
    let taskId: Int
    let status: HealthTask.TaskStatus
    let updatedAt: Date

    var taskID: Int { taskId }
}

struct TaskSyncPayload: Codable, Sendable {
    let tasks: [HealthTask]
    let taskStatuses: [TaskStatusSyncItem]
    let serverTime: Date

}
