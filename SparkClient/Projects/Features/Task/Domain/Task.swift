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
    var notificationEnabled: Bool
    var extra: [String: String]
    var createdAt: Date
    var updatedAt: Date

    var taskMedical: TaskMedical?
    var taskExercise: TaskExercise?
    var taskDiet: TaskDiet?

    // 本地扩展字段
    var localState: LocalState?

    private enum CodingKeys: String, CodingKey {
        case id, member, creator, title, description, type, status, startTime, dueTime
        case repeatType, priority, businessType, businessId, source, notificationId
        case notificationEnabled, extra, createdAt, updatedAt
        case taskMedical, taskExercise, taskDiet, localState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        member = try container.decode(Int.self, forKey: .member)
        creator = try container.decodeIfPresent(Int.self, forKey: .creator)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decode(TaskType.self, forKey: .type)
        status = try container.decode(TaskStatus.self, forKey: .status)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        dueTime = try container.decodeIfPresent(Date.self, forKey: .dueTime)
        repeatType = try container.decode(RepeatType.self, forKey: .repeatType)
        priority = try container.decode(Priority.self, forKey: .priority)
        businessType = try container.decode(String.self, forKey: .businessType)
        businessId = try container.decode(String.self, forKey: .businessId)
        source = try container.decode(Source.self, forKey: .source)
        notificationId = try container.decodeIfPresent(String.self, forKey: .notificationId) ?? ""
        // 旧服务端响应没有该字段时按产品默认值开启，保证升级兼容。
        notificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationEnabled) ?? true
        extra = try container.decodeIfPresent([String: String].self, forKey: .extra) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        taskMedical = try container.decodeIfPresent(TaskMedical.self, forKey: .taskMedical)
        taskExercise = try container.decodeIfPresent(TaskExercise.self, forKey: .taskExercise)
        taskDiet = try container.decodeIfPresent(TaskDiet.self, forKey: .taskDiet)
        localState = try container.decodeIfPresent(LocalState.self, forKey: .localState)
    }

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
    let notificationEnabled: Bool?

    var taskID: Int { taskId }
}

struct TaskSyncPayload: Codable, Sendable {
    let tasks: [HealthTask]
    let taskStatuses: [TaskStatusSyncItem]
    let serverTime: Date

}
