import Foundation

/// 工具人机交互的展示快照（不持久化到聊天消息块）。
enum ToolInteractionSnapshot: Codable, Equatable, Sendable {
    case consent(ExternalToolDataSharePrompt)
    case question(ToolQuestionPrompt)
    case member(ToolMemberSelectionPrompt)
    /// 工具输出详情（只读预览，不阻塞工具执行队列的 continuation）。
    case toolPreview(ToolPreviewPrompt)

    /// `true`：禁止下滑关闭（同意/提问/选成员）；`false`：允许工具详情 Sheet 手势关闭。
    var requiresForcedSheetDismiss: Bool {
        switch self {
        case .toolPreview: return false
        case .consent, .question, .member: return true
        }
    }
}
