import Foundation

nonisolated enum DeepTutorToolName: String, CaseIterable, Sendable {
    case askUser = "ask_user"
    case getCurrentMemberBinding = "get_current_member_binding"
    case requestMemberSelection = "request_member_selection"
    case readMemory = "read_memory"
    case writeMemory = "write_memory"
}

nonisolated struct DeepTutorToolResult: Sendable {
    var content: String
    var metadata: [String: String]
    var success: Bool
    var pauseForUser: DeepTutorToolPauseRequest?

    init(
        content: String,
        metadata: [String: String] = [:],
        success: Bool = true,
        pauseForUser: DeepTutorToolPauseRequest? = nil
    ) {
        self.content = content
        self.metadata = metadata
        self.success = success
        self.pauseForUser = pauseForUser
    }
}

nonisolated enum DeepTutorToolPauseRequest: Sendable {
    case askUser(DeepTutorAskUserPayload)
    case memberSelection(reason: String, arguments: [String: String])
}

nonisolated struct DeepTutorToolContext: Sendable {
    var conversationID: UUID
    var assistantMessageID: UUID
    var userInput: String
    var capability: DeepTutorCapability
    var boundMemberID: Int?
    var hasMemory: Bool
}

nonisolated struct DeepTutorToolRuntimeCompositionResult: Sendable {
    var enabledToolNames: [String]
    var schemas: [AIRuntimeToolDefinition]
    var promptManifest: String
    var reason: String
}
