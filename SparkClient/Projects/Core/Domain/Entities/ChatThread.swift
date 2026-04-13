import Foundation

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let memberID: Int?
    let title: String
    let scenario: AIScenario
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let serverUpdatedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        memberID: Int? = nil,
        title: String,
        scenario: AIScenario = .chat,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.memberID = memberID
        self.title = title
        self.scenario = scenario
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}
