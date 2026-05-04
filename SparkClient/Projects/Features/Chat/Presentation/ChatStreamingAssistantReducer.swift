import Foundation

/// AI 助手**流式输出状态**
/// 保存实时更新的文本、思考、工具与卡片等 blocks 渲染数据
struct ChatStreamingAssistantState: Sendable, Equatable {
    var reasoningContent: String?                 // AI 深度思考内容
    var reasoningStartedAt: Date?                 // 思考开始时间
    var reasoningDurationMs: Int64?               // 思考耗时（毫秒）
    var toolName: String?                         // 当前调用的工具名称
    var toolContent: String?                      // 工具返回内容
    var extraAttachments: [ChatAttachment]        // 运行时扩展字段（预留）
    var blocks: [ChatMessageBlock]                // 消息块（文本/图片/卡片/错误等）

    /// 初始化空状态
    static func initial(kind: ChatMessageKind) -> ChatStreamingAssistantState {
        ChatStreamingAssistantState(
            reasoningContent: nil,
            reasoningStartedAt: nil,
            reasoningDurationMs: nil,
            toolName: nil,
            toolContent: nil,
            extraAttachments: [],
            blocks: []
        )
    }
}

/// 流式输出**状态更新器（Reducer）**
/// 负责把后端推送的增量数据（delta）合并到当前状态
struct ChatStreamingAssistantReducer: Sendable {

    /// 核心：接收增量 delta → 更新 state → 返回是否发生变化
    func reduce(
        state: inout ChatStreamingAssistantState,
        delta: ChatAssistantPartialDelta,
        now: Date = Date()
    ) -> Bool {
        let previous = state                       // 保存旧状态（用于对比是否变化）

        // 1. 更新基础内容
        // 2. 处理思考内容（推理）
        let normalizedReasoning = normalize(delta.reasoning)
        state.reasoningContent = normalizedReasoning
        
        // 如果有思考内容且未开始计时 → 记录开始时间 & 计算耗时
        if let normalizedReasoning, !normalizedReasoning.isEmpty {
            if state.reasoningStartedAt == nil {
                state.reasoningStartedAt = now
            }
            if let startedAt = state.reasoningStartedAt {
                state.reasoningDurationMs = max(1, Int64(now.timeIntervalSince(startedAt) * 1_000))
            }
        }

        // 3. 更新工具信息
        state.toolName = normalize(delta.toolName)
        state.toolContent = normalize(delta.toolContent)

        // 4. 合并并规范化消息块（blocks）→ 供 UI 渲染
        state.blocks = mergeBlocks(
            current: state.blocks,
            delta: delta,
            reasoningDurationMs: state.reasoningDurationMs,
            reasoningVisibility: .full,
            extraAttachments: state.extraAttachments,
            now: now
        )
        state.blocks = ChatMessageBlockBuilder.finalizeStreamingPresentationBlocks(
            normalizeStreamingBlocks(state.blocks)
        )

        // 返回：状态是否变化（用于 UI 刷新）
        return state != previous
    }

    /// 合并增量 blocks 到流式状态
    func mergeAttachments(
        state: inout ChatStreamingAssistantState,
        incomingBlocks: [ChatMessageBlock],
        now: Date = Date()
    ) -> Bool {
        let previous = state
        guard incomingBlocks.isEmpty == false else { return false }
        
        // 重新生成消息块（blocks-only）
        state.blocks = ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: state.blocks,
            incomingBlocks: incomingBlocks
        )

        return state != previous
    }

    /// 高级合并：用于展示层（富文本、卡片块批量更新）
    func mergePresentation(
        state: inout ChatStreamingAssistantState,
        incomingBlocks: [ChatMessageBlock],
        now: Date = Date()
    ) -> Bool {
        let previous = state
        guard incomingBlocks.isEmpty == false else { return false }

        state.blocks = ChatMessageBlockBuilder.finalizeStreamingPresentationBlocks(
            normalizeStreamingBlocks(
                ChatMessageBlockBuilder.mergeRichBlocks(
                    existingBlocks: state.blocks,
                    incomingBlocks: incomingBlocks
                )
            )
        )

        return state != previous
    }

    // MARK: - 私有工具方法

    /// 合并增量 delta 到当前消息块
    private func mergeBlocks(
        current: [ChatMessageBlock],
        delta: ChatAssistantPartialDelta,
        reasoningDurationMs: Int64?,
        reasoningVisibility: ChatReasoningVisibility,
        extraAttachments: [ChatAttachment],
        now: Date
    ) -> [ChatMessageBlock] {
        var blocks = current

        // 1. 处理思考块（reasoning block）
        if let reasoning = normalize(delta.reasoning) {
            let card = ChatDeepThoughtCardPayload(
                reasoningContent: reasoning,
                reasoningDurationMs: reasoningDurationMs,
                reasoningExpanded: false,
                reasoningVisibility: reasoningVisibility
            )
            if let index = blocks.firstIndex(where: { $0.kind == .deepThought }) {
                // 已存在 → 更新
                let old = blocks[index]
                blocks[index] = ChatMessageBlock(
                    id: old.id,
                    anchor: old.anchor,
                    kind: .deepThought,
                    deepThoughtCard: card,
                    createdAt: old.createdAt,
                    updatedAt: now
                )
            } else {
                // 不存在 → 插入到顶部
                blocks.insert(
                    ChatMessageBlock(kind: .deepThought, deepThoughtCard: card, createdAt: now, updatedAt: now),
                    at: 0
                )
            }
        }

        // 2. 处理工具块 / 文本块
        let trimmedAnswer = delta.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        if delta.kind == .tool {
            // 工具块：更新或追加
            let toolText = normalize(delta.toolContent) ?? ""
            if let toolCallID = delta.toolCallID,
               let index = blocks.lastIndex(where: { $0.kind == .tool && $0.toolCallID == toolCallID })
            {
                let old = blocks[index]
                blocks[index] = ChatMessageBlock(
                    id: old.id,
                    anchor: .toolCall(toolCallID),
                    kind: .tool,
                    text: toolText,
                    toolName: normalize(delta.toolName),
                    toolCallID: toolCallID,
                    createdAt: old.createdAt,
                    updatedAt: now
                )
            } else {
                blocks.append(
                    ChatMessageBlock(
                        anchor: delta.toolCallID.map(ChatBlockAnchor.toolCall),
                        kind: .tool,
                        text: toolText,
                        toolName: normalize(delta.toolName),
                        toolCallID: delta.toolCallID,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
        }
        // 文本块：有内容才渲染
        else if !trimmedAnswer.isEmpty {
            if let lastIndex = blocks.indices.last,
               blocks[lastIndex].kind == .text
            {
                // 最后一块是文本 → 更新
                let old = blocks[lastIndex]
                blocks[lastIndex] = ChatMessageBlock(
                    id: old.id,
                    anchor: old.anchor,
                    kind: .text,
                    text: delta.answer,
                    createdAt: old.createdAt,
                    updatedAt: now
                )
            } else {
                // 追加新文本块
                blocks.append(
                    ChatMessageBlock(kind: .text, text: delta.answer, createdAt: now, updatedAt: now)
                )
            }
        }

        // 最终合并构建器（blocks-only）
        let runtimeToolBlocks = runtimeToolBlocks(
            toolName: delta.toolName,
            toolContent: delta.toolContent,
            toolCallID: delta.toolCallID,
            now: now
        )
        return ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: blocks,
            incomingBlocks: runtimeToolBlocks
        )
    }

    /// 字符串规范化：去空、去首尾空白，空值返回 nil
    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// 构建工具运行时块
    private func runtimeToolBlocks(
        toolName: String?,
        toolContent: String?,
        toolCallID: String?,
        now: Date
    ) -> [ChatMessageBlock] {
        guard let toolContent = normalize(toolContent) else { return [] }
        return [
            ChatMessageBlock(
                anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                kind: .tool,
                text: toolContent,
                toolName: normalize(toolName),
                toolCallID: toolCallID,
                createdAt: now,
                updatedAt: now
            )
        ]
    }

    /// 流式块规范化：合并同类块、避免重复、保持结构干净
    private func normalizeStreamingBlocks(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        var normalized: [ChatMessageBlock] = []

        for block in blocks {
            switch block.kind {
            // 文本块：合并连续文本
            case .text:
                if let last = normalized.last, last.kind == .text {
                    normalized[normalized.count-1] = replacing(original: last, with: block)
                    continue
                }
            // 思考块：替换已有思考块
            case .deepThought:
                if let index = normalized.firstIndex(where: { $0.kind == .deepThought }) {
                    normalized[index] = replacing(original: normalized[index], with: block)
                    continue
                }
            // 工具块：按 toolCallID 合并
            case .tool:
                if let id = block.toolCallID,
                   let index = normalized.lastIndex(where: { $0.kind == .tool && $0.toolCallID == id })
                {
                    normalized[index] = replacing(original: normalized[index], with: block)
                    continue
                }
                // 无 ID 工具块：合并最后一块
                if block.toolCallID == nil,
                   let last = normalized.last,
                   last.kind == .tool,
                   last.toolCallID == nil
                {
                    normalized[normalized.count-1] = replacing(original: last, with: block)
                    continue
                }
            // 结构化卡片块：按类型+toolCallID+锚点合并（与睡眠卡同规则；含知识卡/任务卡/待选成员卡）
            case .sleepVisualization, .workoutVisualization, .structuredHealthCards, .captureCard, .knowledgeCards, .html, .taskCards, .pendingMemberToolCards:
                if let index = normalized.lastIndex(where: {
                    $0.kind == block.kind
                    && $0.toolCallID == block.toolCallID
                    && $0.anchor == block.anchor
                }) {
                    normalized[index] = replacing(original: normalized[index], with: block)
                    continue
                }
            default: break
            }

            normalized.append(block)
        }

        return normalized
    }

    /// 用新块内容替换旧块（保留 ID、创建时间）
    private func replacing(original: ChatMessageBlock, with incoming: ChatMessageBlock) -> ChatMessageBlock {
        ChatMessageBlock(
            id: original.id,
            anchor: incoming.anchor ?? original.anchor,
            kind: incoming.kind,
            text: incoming.text,
            toolName: incoming.toolName,
            toolCallID: incoming.toolCallID ?? original.toolCallID,
            attachments: incoming.attachments,
            knowledgeCards: incoming.knowledgeCards,
            taskCards: incoming.taskCards,
            pendingMemberToolCards: incoming.pendingMemberToolCards,
            locations: incoming.locations,
            routes: incoming.routes,
            events: incoming.events,
            healthCards: incoming.healthCards,
            structuredHealthCards: incoming.structuredHealthCards,
            sleepVisualization: incoming.sleepVisualization,
            workoutVisualization: incoming.workoutVisualization,
            captureMessageCard: incoming.captureMessageCard,
            smallTaskCard: incoming.smallTaskCard,
            deepThoughtCard: incoming.deepThoughtCard ?? original.deepThoughtCard,
            createdAt: original.createdAt,
            updatedAt: incoming.updatedAt
        )
    }
}
