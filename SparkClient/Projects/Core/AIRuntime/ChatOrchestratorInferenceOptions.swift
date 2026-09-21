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
    /// 线上问诊的受限采集模式：只允许症状采集工具，不生成诊断、建议或其他普通文本。
    /// 普通智能体/医生对话保持 false，继续使用完整工具编排。
    var symptomCollectionOnly: Bool = false

    static let `default` = ChatOrchestratorInferenceOptions(
        useTools: true,
        useKnowledgeBag: true,
        useWebSearch: true,
        reasoningEnabled: false,
        reasoningEffortTier: 0,
        allowedToolNames: nil,
        symptomCollectionOnly: false
    )
}
