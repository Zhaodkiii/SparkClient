import Foundation

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let patientID: Int?
    let title: String
    let scenario: AIScenario
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        patientID: Int? = nil,
        title: String,
        scenario: AIScenario = .chat,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patientID = patientID
        self.title = title
        self.scenario = scenario
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
