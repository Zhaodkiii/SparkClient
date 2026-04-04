import Foundation

enum ToolAuditStatus: String, Codable, Sendable {
    case success
    case denied
    case failed
}

struct ToolAuditEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let toolName: String
    let patientID: UUID?
    let inputSummary: String
    let outputSummary: String
    let status: ToolAuditStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        toolName: String,
        patientID: UUID?,
        inputSummary: String,
        outputSummary: String,
        status: ToolAuditStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.patientID = patientID
        self.inputSummary = inputSummary
        self.outputSummary = outputSummary
        self.status = status
        self.createdAt = createdAt
    }
}

struct ToolExecutionResult: Sendable {
    let toolName: String
    let outputText: String
    let sensitive: Bool
    let shouldBypassModel: Bool
}

enum ToolHubResult: Sendable {
    case none
    case executed(ToolExecutionResult)
}

