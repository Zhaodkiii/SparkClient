import Foundation

/// `ChatOrchestrator` 使用的推理开关（与 UI 层 `ChatComposerRuntimeFlags` 字段对齐）。
struct ChatOrchestratorInferenceOptions: Equatable, Sendable {
    var useTools: Bool
    var useKnowledgeBag: Bool
    var useWebSearch: Bool
    var reasoningEnabled: Bool
    /// 0 = minimal，1...3 = low/medium/high；与 `AIRuntimeReasoningOptions.effortTier` 对齐。
    var reasoningEffortTier: Int
    /// 非空时仅向模型暴露这些工具名。用于小任务把可调用工具限制在任务维度内。
    var allowedToolNames: Set<String>? = nil

    static let `default` = ChatOrchestratorInferenceOptions(
        useTools: true,
        useKnowledgeBag: true,
        useWebSearch: true,
        reasoningEnabled: false,
        reasoningEffortTier: 0,
        allowedToolNames: nil
    )
}
