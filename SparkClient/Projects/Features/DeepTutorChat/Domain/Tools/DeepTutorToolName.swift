import Foundation

nonisolated enum DeepTutorToolName: String, CaseIterable, Sendable {
    case askUser = "ask_user"
    case getCurrentMemberBinding = "get_current_member_binding"
    case queryMemberProfile = "query_member_profile"
    case requestMemberSelection = "request_member_selection"
    case readMemory = "read_memory"
    case showCustomMessageCard = "show_custom_message_card"
    case writeMemory = "write_memory"

    nonisolated var displayTitle: String {
        switch self {
        case .askUser:
            return "向你提问"
        case .getCurrentMemberBinding:
            return "检查当前成员"
        case .queryMemberProfile:
            return "查询成员医疗资料"
        case .requestMemberSelection:
            return "选择成员"
        case .readMemory:
            return "读取记忆"
        case .showCustomMessageCard:
            return "展示上传拍摄卡片"
        case .writeMemory:
            return "写入记忆"
        }
    }

    nonisolated static func displayTitle(for rawValue: String) -> String {
        Self(rawValue: rawValue)?.displayTitle ?? SparkToolName.displayName(for: rawValue)
    }
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
    case attachmentCapture(cardType: DeepTutorCaptureCardType)
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
