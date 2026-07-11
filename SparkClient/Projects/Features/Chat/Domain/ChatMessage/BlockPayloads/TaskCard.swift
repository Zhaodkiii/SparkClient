import Foundation

// MARK: - AI 任务卡片（仅客户端消息内展示，不落服务端 TaskCard 表）

nonisolated struct TaskCard: Identifiable, Codable, Equatable, Sendable {
    enum CardStatus: Int, Codable, Sendable {
        case pending = 0
        case confirmed = 1
        case ignored = 2
        case expired = 3
    }

    let id: Int
    var member: Int?
    let creator: Int?
    var title: String
    var description: String
    var type: HealthTask.TaskType
    var startTime: Date?
    var dueTime: Date?
    var repeatType: HealthTask.RepeatType
    var priority: HealthTask.Priority
    var businessType: String
    var businessId: String
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

    enum Action: Equatable, Sendable {
        case confirm(TaskCard)
        case ignore(TaskCard)
        case setMember(TaskCard, Int?)
    }

    var businessID: String {
        get { businessId }
        set { businessId = newValue }
    }
}
