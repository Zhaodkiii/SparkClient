import Foundation

/// 流式助手状态：承载“当前已拼接的增量结果”。
/// 说明：
/// - content 是最终回答正文的增量累积值；
/// - reasoningContent 是思考链的增量累积值；
/// - reasoningStartedAt/reasoningDurationMs 用于实时显示思考耗时。
struct ChatStreamingAssistantState: Sendable, Equatable {
    var kind: ChatMessageKind
    var content: String
    var reasoningContent: String?
    var reasoningStartedAt: Date?
    var reasoningDurationMs: Int64?
    var toolName: String?
    var toolContent: String?

    static func initial(kind: ChatMessageKind) -> ChatStreamingAssistantState {
        ChatStreamingAssistantState(
            kind: kind,
            content: "",
            reasoningContent: nil,
            reasoningStartedAt: nil,
            reasoningDurationMs: nil,
            toolName: nil,
            toolContent: nil
        )
    }
}

/// 流式增量归并器（状态机）：
/// - 输入 `ChatAssistantPartialDelta`；
/// - 输出更新后的 `ChatStreamingAssistantState`；
/// - 保证流式展示链路对字段清洗、计时与变更判定一致。
struct ChatStreamingAssistantReducer: Sendable {
    /// 将一条增量合并到当前状态。
    /// - Returns: 若状态发生变化返回 `true`，上层可据此触发 UI 刷新。
    func reduce(
        state: inout ChatStreamingAssistantState,
        delta: ChatAssistantPartialDelta,
        now: Date = Date()
    ) -> Bool {
        let previous = state

        state.kind = delta.kind
        state.content = delta.answer

        let normalizedReasoning = normalize(delta.reasoning)
        state.reasoningContent = normalizedReasoning

        if let normalizedReasoning, normalizedReasoning.isEmpty == false {
            if state.reasoningStartedAt == nil {
                state.reasoningStartedAt = now
            }
            if let startedAt = state.reasoningStartedAt {
                state.reasoningDurationMs = max(1, Int64(now.timeIntervalSince(startedAt) * 1_000))
            }
        }

        state.toolName = normalize(delta.toolName)
        state.toolContent = normalize(delta.toolContent)

        return state != previous
    }

    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
