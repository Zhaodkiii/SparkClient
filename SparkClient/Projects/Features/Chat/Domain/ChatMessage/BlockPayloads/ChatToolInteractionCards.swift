import Foundation

nonisolated enum ChatInlineToolCardStatus: String, Codable, Sendable {
    case pending
    case submitted
    case cancelled
    case expired
}

nonisolated struct ChatToolQuestionCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let completionID: UUID
    let prompt: ToolQuestionPrompt
    var answers: [ToolQuestionResponse]
    var status: ChatInlineToolCardStatus
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case completionID = "completionId"
        case prompt
        case answers
        case status
        case resultText
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        completionID: UUID,
        prompt: ToolQuestionPrompt,
        answers: [ToolQuestionResponse] = [],
        status: ChatInlineToolCardStatus = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.completionID = completionID
        self.prompt = prompt
        self.answers = answers
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ChatToolMemberSelectionCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let completionID: UUID
    let prompt: ToolMemberSelectionPrompt
    var selectedMemberID: Int?
    var selectedMemberName: String?
    var status: ChatInlineToolCardStatus
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case completionID = "completionId"
        case prompt
        case selectedMemberID = "selectedMemberId"
        case selectedMemberName
        case status
        case resultText
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        completionID: UUID,
        prompt: ToolMemberSelectionPrompt,
        selectedMemberID: Int? = nil,
        selectedMemberName: String? = nil,
        status: ChatInlineToolCardStatus = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.completionID = completionID
        self.prompt = prompt
        self.selectedMemberID = selectedMemberID
        self.selectedMemberName = selectedMemberName
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ChatHealthResourceCandidateSelectionCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let completionID: UUID
    let prompt: HealthResourceToolCandidatePrompt
    var selectedCandidates: [HealthResourceToolCandidateDTO]
    var status: ChatInlineToolCardStatus
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case completionID = "completionId"
        case prompt
        case selectedCandidates
        case status
        case resultText
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        completionID: UUID,
        prompt: HealthResourceToolCandidatePrompt,
        selectedCandidates: [HealthResourceToolCandidateDTO] = [],
        status: ChatInlineToolCardStatus = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.completionID = completionID
        self.prompt = prompt
        self.selectedCandidates = selectedCandidates
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ChatToolConsentCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let completionID: UUID
    let prompt: ExternalToolDataSharePrompt
    var decision: ToolConsentDecision?
    var status: ChatInlineToolCardStatus
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case completionID = "completionId"
        case prompt
        case decision
        case status
        case resultText
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        completionID: UUID,
        prompt: ExternalToolDataSharePrompt,
        decision: ToolConsentDecision? = nil,
        status: ChatInlineToolCardStatus = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.completionID = completionID
        self.prompt = prompt
        self.decision = decision
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
