import Foundation

struct PendingMemberToolCard: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case running
        case completed
    }

    let id: UUID
    let toolName: String
    var arguments: [String: String]
    let toolCallID: String?
    let resumeMessages: [AIRuntimeMessage]
    let reason: String
    var selectedMemberID: Int?
    var status: Status
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: String],
        toolCallID: String? = nil,
        resumeMessages: [AIRuntimeMessage] = [],
        reason: String,
        selectedMemberID: Int? = nil,
        status: Status = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.toolCallID = toolCallID
        self.resumeMessages = resumeMessages
        self.reason = reason
        self.selectedMemberID = selectedMemberID
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
