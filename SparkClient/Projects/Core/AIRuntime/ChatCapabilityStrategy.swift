import Foundation

/// Capability 层输入：由 `SendChatMessageUseCase` 组装后交给策略对象。
struct ChatCapabilityStrategyInput: Sendable {
    let inference: ChatOrchestratorInferenceOptions
    let modelAllowedToolNames: Set<String>?
    let history: [ChatMessage]
    let threadID: UUID
    let userQuestionForAI: String
    /// 问报告路径：已解析出非空 `healthResourceContext`。
    let hasHealthResourceContext: Bool
}

/// Capability 层输出：本轮 AI 编排所需的 history 与 inference 策略。
struct ChatCapabilityStrategyOutput: Sendable {
    let inference: ChatOrchestratorInferenceOptions
    let aiHistory: [ChatMessage]
}

/// Capability 策略：决定本轮“做什么”（工具白名单、历史窗口、推理开关），不执行工具。
protocol ChatCapabilityStrategy: Sendable {
    var name: String { get }
    func plan(_ input: ChatCapabilityStrategyInput) -> ChatCapabilityStrategyOutput
}

/// 标准聊天 capability：使用完整历史，Composer 开关 + 模型工具白名单。
struct StandardChatCapabilityStrategy: ChatCapabilityStrategy {
    let name = "chat"

    func plan(_ input: ChatCapabilityStrategyInput) -> ChatCapabilityStrategyOutput {
        ChatCapabilityStrategyOutput(
            inference: input.inference.withAllowedToolNames(input.modelAllowedToolNames),
            aiHistory: input.history
        )
    }
}

/// 问报告 capability：显式标记问报告子场景；`plan()` 与标准聊天等价，不改 scenario / 历史。
struct ReportInterpretationCapabilityStrategy: ChatCapabilityStrategy {
    let name = "report_interpretation"

    func plan(_ input: ChatCapabilityStrategyInput) -> ChatCapabilityStrategyOutput {
        StandardChatCapabilityStrategy().plan(input)
    }
}

/// 小任务 capability：合成单轮用户消息，工具白名单为小任务列表与模型白名单交集。
struct SmallTaskCapabilityStrategy: ChatCapabilityStrategy {
    let name = "small_task"
    let smallTask: SmallTask

    func plan(_ input: ChatCapabilityStrategyInput) -> ChatCapabilityStrategyOutput {
        let aiHistory = [
            ChatMessage(
                threadID: input.threadID,
                role: .user,
                blocks: [.init(kind: .text, text: input.userQuestionForAI)],
                deliveryState: .pending,
                modelName: "user"
            )
        ]
        let allowedToolNames = Set(smallTask.toolList).intersection(
            input.modelAllowedToolNames ?? Set(smallTask.toolList)
        )
        let inference = ChatOrchestratorInferenceOptions(
            useTools: smallTask.toolList.isEmpty == false,
            useKnowledgeBag: input.inference.useKnowledgeBag,
            useWebSearch: input.inference.useWebSearch,
            reasoningEnabled: input.inference.reasoningEnabled,
            reasoningEffortTier: input.inference.reasoningEffortTier,
            allowedToolNames: allowedToolNames
        )
        return ChatCapabilityStrategyOutput(inference: inference, aiHistory: aiHistory)
    }
}

enum ChatCapabilityStrategyResolver {
    static func resolve(
        smallTask: SmallTask?,
        hasHealthResourceContext: Bool = false
    ) -> ChatCapabilityStrategy {
        if let smallTask {
            return SmallTaskCapabilityStrategy(smallTask: smallTask)
        }
        if hasHealthResourceContext {
            return ReportInterpretationCapabilityStrategy()
        }
        return StandardChatCapabilityStrategy()
    }
}

extension ChatOrchestratorInferenceOptions {
    func withAllowedToolNames(_ allowedToolNames: Set<String>?) -> Self {
        var copy = self
        copy.allowedToolNames = allowedToolNames
        return copy
    }

    static func from(composerFlags: ChatComposerRuntimeFlags) -> Self {
        ChatOrchestratorInferenceOptions(
            useTools: composerFlags.useTools,
            useKnowledgeBag: composerFlags.useKnowledgeBag,
            useWebSearch: composerFlags.useWebSearch,
            reasoningEnabled: composerFlags.reasoningEnabled,
            reasoningEffortTier: composerFlags.reasoningEffortTier
        )
    }
}
