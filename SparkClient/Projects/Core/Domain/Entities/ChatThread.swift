import Foundation

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let memberID: Int?
    let title: String
    let scenario: AIScenario
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        memberID: Int? = nil,
        title: String,
        scenario: AIScenario = .chat,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.title = title
        self.scenario = scenario
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
