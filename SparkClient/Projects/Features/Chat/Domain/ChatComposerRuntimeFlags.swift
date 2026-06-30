import Foundation

/// 每会话输入栏上的推理与模型选择状态（持久在 `ChatComposerDraft` 中）。
struct ChatComposerRuntimeFlags: Equatable, Sendable {
    var useTools: Bool = false
    var useKnowledgeBag: Bool = true
    var useWebSearch: Bool = true
    var reasoningEnabled: Bool = false
    /// 0 = minimal（不思考），1 = low，2 = medium，3 = high（与豆包/OpenAI 等 `reasoning_effort` 对齐）。
    var reasoningEffortTier: Int = 1
    /// `nil` 表示使用配置解析的默认模型（不强制 runtime override）。
    var selectedChatModelName: String?
}
