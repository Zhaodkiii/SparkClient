import Foundation

/// 工具人机交互的展示快照（不持久化到聊天消息块）。
enum ToolInteractionSnapshot: Codable, Equatable, Sendable {
    case consent(ExternalToolDataSharePrompt)
    case question(ToolQuestionPrompt)
    case member(ToolMemberSelectionPrompt)
}
