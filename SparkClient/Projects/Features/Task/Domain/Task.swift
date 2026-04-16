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
    var businessID: String
    var source: Source
    var notificationID: String
    var extra: [String: String]
    var createdAt: Date
    var updatedAt: Date

    var taskMedical: TaskMedical?
    var taskExercise: TaskExercise?
    var taskDiet: TaskDiet?

    // 本地扩展字段
    var localState: LocalState?

    enum CodingKeys: String, CodingKey {
        case id
        case member
        case creator
        case title
        case description
        case type
        case status
        case startTime = "start_time"
        case dueTime = "due_time"
        case repeatType = "repeat_type"
        case priority
        case businessType = "business_type"
        case businessID = "business_id"
        case source
        case notificationID = "notification_id"
        case extra
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case taskMedical = "task_medical"
        case taskExercise = "task_exercise"
        case taskDiet = "task_diet"
        case localState = "local_state"
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

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case reminderTime = "reminder_time"
        case medicalTaskType = "medical_task_type"
        case description
        case source
        case extra
    }
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

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case exerciseType = "exercise_type"
        case durationMin = "duration_min"
        case intensity
        case description
        case source
        case extra
    }
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

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case mealType = "meal_type"
        case calorieTarget = "calorie_target"
        case foodRecommend = "food_recommend"
        case description
        case source
        case extra
    }
}

// MARK: - AI 任务卡片（仅客户端消息内展示，不落服务端 TaskCard 表）

struct TaskCard: Identifiable, Codable, Equatable, Sendable {
    enum CardStatus: Int, Codable, Sendable {
        case pending = 0
        case confirmed = 1
        case ignored = 2
        case expired = 3
    }

    let id: Int
    let member: Int
    let creator: Int?
    var title: String
    var description: String
    var type: HealthTask.TaskType
    var startTime: Date?
    var dueTime: Date?
    var repeatType: HealthTask.RepeatType
    var priority: HealthTask.Priority
    var businessType: String
    var businessID: String
    var source: HealthTask.Source
    var status: CardStatus
    var extractPayload: [String: String]
    var taskPayload: [String: String]
    var similarityPayload: [String: String]
    var ignoredReason: String
    var confirmedTask: Int?
    var createdAt: Date
    var updatedAt: Date

    var localState: HealthTask.LocalState?

    enum CodingKeys: String, CodingKey {
        case id
        case member
        case creator
        case title
        case description
        case type
        case startTime = "start_time"
        case dueTime = "due_time"
        case repeatType = "repeat_type"
        case priority
        case businessType = "business_type"
        case businessID = "business_id"
        case source
        case status
        case extractPayload = "extract_payload"
        case taskPayload = "task_payload"
        case similarityPayload = "similarity_payload"
        case ignoredReason = "ignored_reason"
        case confirmedTask = "confirmed_task"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case localState = "local_state"
    }
}

struct TaskStatusSyncItem: Codable, Sendable {
    let taskID: Int
    let status: HealthTask.TaskStatus
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case status
        case updatedAt = "updated_at"
    }
}

struct TaskSyncPayload: Codable, Sendable {
    let tasks: [HealthTask]
    let taskStatuses: [TaskStatusSyncItem]
    let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case tasks
        case taskStatuses = "task_statuses"
        case serverTime = "server_time"
    }
}
