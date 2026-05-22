import Foundation

/// 工具人机交互的展示快照（不持久化到聊天消息块）。
enum ToolInteractionSnapshot: Codable, Equatable, Sendable {
    case consent(ExternalToolDataSharePrompt)
    case question(ToolQuestionPrompt)
    case member(ToolMemberSelectionPrompt)
    /// 工具输出详情（只读预览，不阻塞工具执行队列的 continuation）。
    case toolPreview(ToolPreviewPrompt)
    /// 当前会话系统消息设置（只维护会话级提示词；智能体提示词只读展示）。
    case systemMessageSettings(SystemMessageSettingsPrompt)
    /// M11：`list_member_health_sources` 多条候选，用户勾选后加入预览草稿。
    case healthResourceCandidates(HealthResourceToolCandidatePrompt)
    /// 手动「问报告」资料选择（与工具候选共用呈现队列）。
    case askReportPicker(AskReportPickerPrompt)

    /// `true`：禁止下滑关闭（同意/提问/选成员）；`false`：允许工具详情 Sheet 手势关闭。
    var requiresForcedSheetDismiss: Bool {
        switch self {
        case .toolPreview, .systemMessageSettings, .healthResourceCandidates, .askReportPicker: return false
        case .consent, .question, .member: return true
        }
    }
}
