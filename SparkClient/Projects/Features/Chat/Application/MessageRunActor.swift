import Foundation

enum ChatRunEvent: Sendable {
    case assistantPartial(ChatAssistantPartialDelta, assistantClientMessageID: UUID)
    case richBlockReady(ChatMessageBlock, assistantClientMessageID: UUID)
    case structuredHealthCardsDelta(StructuredHealthCardsBlob, threadID: UUID, assistantClientMessageID: UUID)
    case finalizeAssistantBlocks([ChatMessageBlock], assistantClientMessageID: UUID)
}

/// Serializes all message-block side effects for one AI run.
///
/// The chat UI never receives tool-card mutations directly. Runtime text deltas,
/// tool rows, and async rich-card results are converted into `ChatRunEvent`s and
/// written through this actor into the repository. Core Data notifications then
/// refresh the projected timeline. Because every event targets a stable block ID
/// and `upsertMessageBlock` ignores stale revisions, a late health card or a
/// duplicated network callback can only update its own block; it cannot create a
/// second shadow card or overwrite newer streaming text.
actor MessageRunActor {
    private let repository: any ChatRepository
    private let logger: Logger
    private var pendingPartials: [UUID: ChatAssistantPartialDelta] = [:]
    private var partialFlushTasks: [UUID: Task<Void, Never>] = [:]
    private var runStates: [UUID: AssistantRunState] = [:]
    private let partialFlushIntervalNs: UInt64 = 50_000_000

    init(repository: any ChatRepository, logger: Logger = ConsoleLogger()) {
        self.repository = repository
        self.logger = logger
    }

    func startAssistantMessage(
        threadID: UUID,
        assistantClientMessageID: UUID,
        modelName: String,
        createdAt: Date = Date()
    ) async throws {
        runStates[assistantClientMessageID] = AssistantRunState(threadID: threadID)
        _ = try await repository.upsertLocalMessage(
            ChatMessage(
                id: assistantClientMessageID,
                threadID: threadID,
                role: .assistant,
                blocks: [],
                clientMessageID: assistantClientMessageID,
                serverMessageID: nil,
                deliveryState: .sending,
                createdAt: createdAt,
                modelName: modelName
            )
        )
    }

    /// 处理聊天运行事件（接收AI助手各种输出事件：增量文本、富文本块、健康卡片、最终定稿）
    /// - Parameter event: 聊天运行事件
    func apply(_ event: ChatRunEvent) async {
        // 根据事件类型分发处理
        switch event {
            
        // MARK: - 助手增量文本片段（流式输出：打字机效果）
        case .assistantPartial(let delta, let assistantClientMessageID):
            // 将增量文本片段加入队列，累积完整回答
            enqueueAssistantPartial(delta, assistantClientMessageID: assistantClientMessageID)
            
        // MARK: - 富内容块就绪（图片/卡片/工具等非文本块）
        case .richBlockReady(let block, let assistantClientMessageID):
            // 插入/更新富消息块到数据库
            // markPendingForSync: 标记为待同步，后续会上传到服务端
            await repository.upsertMessageBlock(
                clientMessageID: assistantClientMessageID,
                block: Self.databaseRichBlock(block, assistantClientMessageID: assistantClientMessageID),
                markPendingForSync: true
            )
            
        // MARK: - 结构化健康卡片增量更新（睡眠/健康数据可视化卡片）
        case .structuredHealthCardsDelta(let delta, let threadID, let assistantClientMessageID):
            // 合并健康卡片增量数据（实时更新健康图表/数据）
            await mergeStructuredHealthCardsDelta(
                delta,
                threadID: threadID,
                assistantClientMessageID: assistantClientMessageID
            )
            
        // MARK: - 助手消息最终定稿（所有流式输出完成，整理并持久化最终消息）
        case .finalizeAssistantBlocks(let blocks, let assistantClientMessageID):
            // 1. 刷新并清空累积的增量文本片段，确保无残留
            await flushAssistantPartial(assistantClientMessageID: assistantClientMessageID)
            
            // 2. 获取当前消息的运行状态（保存文本片段、顺序、工具调用关系）
            var state = runStates[assistantClientMessageID] ?? AssistantRunState(threadID: nil)
            
            // 3. 兜底逻辑：如果状态中没有累积文本，但最终块里有有效文本，则直接使用
            if state.textSegmentsForFinalization().isEmpty,
               let finalText = blocks.first(where: { $0.kind == .text })?.text,
               finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                // 消费兜底文本，加入状态管理
                _ = state.consumeAnswer(finalText)
            }
            
            // 4. 生成时间戳与修订版本号，用于消息块排序与更新
            let now = Date()
            let revision = Self.revision(now)
            
            // 5. 持久化【最终定稿的文本片段】到数据库
            for segment in state.textSegmentsForFinalization() {
                await repository.upsertMessageBlock(
                    clientMessageID: assistantClientMessageID,
                    block: ChatMessageBlock(
                        id: ChatStableBlockID.textSegment(messageID: assistantClientMessageID, index: segment.index),
                        kind: .text,         // 文本类型块
                        text: segment.text,  // 片段内容
                        nodeRole: .timeline, // 角色：时间线展示
                        status: .ready,      // 状态：就绪
                        revision: revision,  // 修订版本
                        orderKey: segment.orderKey, // 排序键（保证展示顺序）
                        createdAt: now,
                        updatedAt: now
                    ),
                    markPendingForSync: true
                )
            }
            
            // 6. 持久化【非文本块】（工具调用、富媒体、卡片等）
            for block in blocks {
                // 跳过文本块（文本已在上一步处理）
                guard block.kind != .text else { continue }
                
                // 如果是工具调用块，使用状态中记录的排序键，保证与文本顺序一致
                let orderKeyOverride = block.toolCallID.flatMap { state.orderKeyIfKnown(forToolCallID: $0) }
                
                // 插入/更新最终定稿的助手消息块
                await repository.upsertMessageBlock(
                    clientMessageID: assistantClientMessageID,
                    block: Self.finalizedAssistantBlock(
                        block,
                        assistantClientMessageID: assistantClientMessageID,
                        orderKeyOverride: orderKeyOverride
                    ),
                    markPendingForSync: true
                )
                await upsertPendingStructuredHealthCardIfNeeded(
                    toolName: block.toolName,
                    toolCallID: block.toolCallID,
                    assistantClientMessageID: assistantClientMessageID,
                    revision: revision,
                    createdAt: now
                )
            }

            // 运行时流式已结束，消息不应继续暴露为 `.sending`。
            // 后续网络同步由 outbox 接管：先标记 `.pending`，push 成功后再变为 `.sent`。
            await repository.updateMessageDeliveryState(
                clientMessageID: assistantClientMessageID,
                state: .pending
            )
            
            // 7. 清理：消息已定稿，移除运行状态，释放内存
            runStates.removeValue(forKey: assistantClientMessageID)
        }
    }

    private func enqueueAssistantPartial(
        _ delta: ChatAssistantPartialDelta,
        assistantClientMessageID: UUID
    ) {
        pendingPartials[assistantClientMessageID] = delta
        guard partialFlushTasks[assistantClientMessageID] == nil else { return }
        partialFlushTasks[assistantClientMessageID] = Task { [partialFlushIntervalNs] in
            try? await Task.sleep(nanoseconds: partialFlushIntervalNs)
            guard Task.isCancelled == false else { return }
            await self.flushAssistantPartial(assistantClientMessageID: assistantClientMessageID)
        }
    }

    private func flushAssistantPartial(assistantClientMessageID: UUID) async {
        partialFlushTasks[assistantClientMessageID]?.cancel()
        partialFlushTasks[assistantClientMessageID] = nil
        guard let delta = pendingPartials.removeValue(forKey: assistantClientMessageID) else { return }
        await persistAssistantPartial(delta, assistantClientMessageID: assistantClientMessageID)
    }

    private func persistAssistantPartial(
        _ delta: ChatAssistantPartialDelta,
        assistantClientMessageID: UUID
    ) async {
        let now = Date()
        let revision = Self.revision(now)
        var state = runStates[assistantClientMessageID] ?? AssistantRunState(threadID: nil)
        let appendedText = state.consumeAnswer(delta.answer)
        if appendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let segment = state.currentTextSegment
            await repository.upsertMessageBlock(
                clientMessageID: assistantClientMessageID,
                block: ChatMessageBlock(
                    id: ChatStableBlockID.textSegment(messageID: assistantClientMessageID, index: segment.index),
                    kind: .text,
                    text: segment.text,
                    nodeRole: .timeline,
                    status: .streaming,
                    revision: revision,
                    orderKey: segment.orderKey,
                    createdAt: now,
                    updatedAt: now
                ),
                markPendingForSync: false
            )
        }

        let reasoning = delta.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reasoning.isEmpty == false {
            await repository.upsertMessageBlock(
                clientMessageID: assistantClientMessageID,
                block: ChatMessageBlock(
                    id: ChatStableBlockID.reasoning(messageID: assistantClientMessageID),
                    kind: .deepThought,
                    text: reasoning,
                    nodeRole: .timeline,
                    deepThoughtCard: ChatDeepThoughtCardPayload(
                        reasoningContent: reasoning,
                        reasoningDurationMs: nil,
                        reasoningExpanded: false,
                        reasoningVisibility: .full
                    ),
                    status: .streaming,
                    revision: revision,
                    orderKey: 900,
                    createdAt: now,
                    updatedAt: now
                ),
                markPendingForSync: false
            )
        }

        guard delta.kind == .tool,
              let toolCallID = delta.toolCallID?.trimmingCharacters(in: .whitespacesAndNewlines),
              toolCallID.isEmpty == false else {
            runStates[assistantClientMessageID] = state
            return
        }
        let toolOrderKey = state.orderKeyForToolCall(toolCallID)
        runStates[assistantClientMessageID] = state
        await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: ChatMessageBlock(
                id: ChatStableBlockID.tool(messageID: assistantClientMessageID, toolCallID: toolCallID),
                anchor: .messageEnd,
                kind: .tool,
                text: delta.toolContent,
                toolName: delta.toolName,
                toolCallID: toolCallID,
                nodeRole: .tool,
                status: .streaming,
                revision: revision,
                orderKey: toolOrderKey,
                createdAt: now,
                updatedAt: now
            ),
            markPendingForSync: false
        )
        await upsertPendingStructuredHealthCardIfNeeded(
            toolName: delta.toolName,
            toolCallID: toolCallID,
            assistantClientMessageID: assistantClientMessageID,
            revision: revision,
            createdAt: now
        )
    }

    /// 合并结构化健康卡片的增量数据（药品、处方、检查报告、病历 流式合并）
    /// - Parameters:
    ///   - delta: 健康卡片增量数据（本次新增的内容）
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息客户端ID
    private func mergeStructuredHealthCardsDelta(
        _ delta: StructuredHealthCardsBlob,
        threadID: UUID,
        assistantClientMessageID: UUID
    ) async {
        // 1. 加载当前会话下的所有消息
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        
        // 2. 查找对应的助手消息：必须先存在消息才能合并卡片
        guard let message = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else {
            // 找不到消息 → 丢弃本次增量，打印警告日志
            logger.warning("结构化健康卡片增量丢弃：assistant message 尚未创建，clientMessageID=\(assistantClientMessageID)", module: .general)
            return
        }

        // 3. 读取消息中已存在的健康卡片数据（如果有）
        var blob: StructuredHealthCardsBlob
        if let existing = message.blocks.last(where: { $0.kind == .structuredHealthCards })?.structuredHealthCards {
            // 已有卡片 → 使用现有数据继续追加
            blob = existing
        } else {
            // 无卡片 → 创建空的健康卡片容器
            blob = StructuredHealthCardsBlob(
                medications: [],       // 药品
                prescriptions: [],    // 处方
                examReports: [],       // 检查报告
                medicalCases: []       // 病历
            )
        }
        
        // 4. 合并增量数据：将本次新增内容追加到原有卡片中
        blob.medications.append(contentsOf: delta.medications)
        blob.prescriptions.append(contentsOf: delta.prescriptions)
        blob.examReports.append(contentsOf: delta.examReports)
        blob.medicalCases.append(contentsOf: delta.medicalCases)

        // 5. 构建新的健康卡片消息块（覆盖式更新）
        let now = Date()
        let block = ChatMessageBlock(
            id: ChatStableBlockID.rich(
                messageID: assistantClientMessageID,
                kind: .structuredHealthCards
            ),
            kind: .structuredHealthCards,        // 块类型：结构化健康卡片
            nodeRole: .toolPresentation,          // 角色：工具展示类内容
            structuredHealthCards: blob,          // 合并后的完整健康数据
            status: .ready,                       // 状态：就绪
            revision: Self.revision(now),         // 数据修订版本
            orderKey: Self.defaultOrderKey(for: .structuredHealthCards), // 排序键
            createdAt: message.createdAt,          // 创建时间沿用消息原时间
            updatedAt: now                        // 更新时间为当前时间
        )
        
        // 6. 插入/更新到数据库，并标记为待同步
        await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: block,
            markPendingForSync: true
        )
    }

    private func upsertPendingStructuredHealthCardIfNeeded(
        toolName: String?,
        toolCallID: String?,
        assistantClientMessageID: UUID,
        revision: Int64,
        createdAt: Date
    ) async {
        guard toolName == SparkToolName.generateStructuredHealthCard.rawValue,
              let toolCallID,
              toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: ChatMessageBlock(
                id: ChatStableBlockID.rich(
                    messageID: assistantClientMessageID,
                    toolCallID: toolCallID,
                    kind: .structuredHealthCards
                ),
                anchor: .toolCall(toolCallID),
                kind: .structuredHealthCards,
                toolCallID: toolCallID,
                parentToolCallID: toolCallID,
                parentBlockID: ChatStableBlockID.tool(messageID: assistantClientMessageID, toolCallID: toolCallID),
                nodeRole: .toolPresentation,
                structuredHealthCards: .empty,
                status: .pending,
                revision: revision,
                orderKey: Self.defaultOrderKey(for: .structuredHealthCards),
                createdAt: createdAt,
                updatedAt: Date()
            ),
            markPendingForSync: true
        )
    }

    private static func finalizedAssistantBlock(
        _ block: ChatMessageBlock,
        assistantClientMessageID: UUID,
        orderKeyOverride: Double? = nil
    ) -> ChatMessageBlock {
        let now = Date()
        let revision = max(block.revision + 1, Self.revision(now))
        switch block.kind {
        case .text:
            return ChatMessageBlock(
                id: block.id,
                kind: .text,
                text: block.text,
                nodeRole: .timeline,
                status: .ready,
                revision: revision,
                orderKey: block.orderKey ?? 1_000,
                createdAt: block.createdAt,
                updatedAt: now
            )
        case .deepThought:
            return ChatMessageBlock(
                id: ChatStableBlockID.reasoning(messageID: assistantClientMessageID),
                kind: .deepThought,
                text: block.deepThoughtCard?.reasoningContent ?? block.text,
                nodeRole: .timeline,
                deepThoughtCard: block.deepThoughtCard,
                status: .ready,
                revision: revision,
                orderKey: block.orderKey ?? 900,
                createdAt: block.createdAt,
                updatedAt: now
            )
        case .tool:
            let id = block.toolCallID.map {
                ChatStableBlockID.tool(messageID: assistantClientMessageID, toolCallID: $0)
            } ?? block.id
            return ChatMessageBlock(
                id: id,
                anchor: block.anchor,
                kind: .tool,
                text: block.text,
                toolName: block.toolName,
                toolCallID: block.toolCallID,
                nodeRole: .tool,
                status: .ready,
                revision: revision,
                orderKey: orderKeyOverride ?? block.orderKey ?? 2_000,
                createdAt: block.createdAt,
                updatedAt: now
            )
        default:
            return databaseRichBlock(block, assistantClientMessageID: assistantClientMessageID)
        }
    }

    static func databaseRichBlock(
        _ block: ChatMessageBlock,
        assistantClientMessageID: UUID
    ) -> ChatMessageBlock {
        let now = Date()
        let revision = max(block.revision + 1, Self.revision(now))
        let stableID: UUID
        if let toolCallID = block.toolCallID {
            stableID = ChatStableBlockID.rich(
                messageID: assistantClientMessageID,
                toolCallID: toolCallID,
                kind: block.kind
            )
        } else {
            stableID = ChatStableBlockID.rich(messageID: assistantClientMessageID, kind: block.kind)
        }
        let normalized = block.normalizedForToolPresentation(assistantClientMessageID: assistantClientMessageID)
        return normalized.replacingPayload(
            normalized.payload,
            status: block.status,
            revision: revision,
            updatedAt: now
        ).replacingIdentity(
            id: stableID,
            orderKey: block.orderKey ?? defaultOrderKey(for: block.kind)
        )
    }

    private static func defaultOrderKey(for kind: ChatMessageBlockKind) -> Double {
        switch kind {
        case .deepThought:
            return 900
        case .text:
            return 1_000
        case .tool:
            return 2_000
        case .structuredHealthCards, .sleepVisualization, .workoutVisualization,
                .captureCard, .knowledgeCards, .html, .taskCards,
                .pendingMemberToolCards:
            return 2_100
        default:
            return 3_000
        }
    }

    private static func revision(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000)
    }

}

nonisolated private struct AssistantRunState {
    struct TextSegment {
        let index: Int
        var text: String
        let orderKey: Double
    }

    let threadID: UUID?
    private(set) var lastAnswer = ""
    private(set) var currentTextSegment = TextSegment(index: 0, text: "", orderKey: 1_000)
    private var completedTextSegments: [TextSegment] = []
    private var nextSegmentIndex = 1
    private var nextOrderKey: Double = 2_000
    private var toolOrderKeys: [String: Double] = [:]

    init(threadID: UUID?) {
        self.threadID = threadID
    }

    mutating func consumeAnswer(_ answer: String) -> String {
        let suffix = suffixToAppend(from: answer)
        lastAnswer = answer
        guard suffix.isEmpty == false else { return "" }
        currentTextSegment.text.append(suffix)
        return suffix
    }

    private func suffixToAppend(from answer: String) -> String {
        if answer.hasPrefix(lastAnswer) {
            return String(answer.dropFirst(lastAnswer.count))
        }

        let emitted = emittedText
        guard emitted.isEmpty == false else { return answer }
        if answer.hasPrefix(emitted) {
            return String(answer.dropFirst(emitted.count))
        }
        if emitted.hasSuffix(answer) {
            return ""
        }

        let commonPrefix = Self.commonPrefixLength(emitted, answer)
        if commonPrefix >= 64 {
            return String(answer.dropFirst(commonPrefix))
        }

        let overlap = Self.suffixPrefixOverlapLength(emitted, answer)
        if overlap >= 64 {
            return String(answer.dropFirst(overlap))
        }

        return answer
    }

    private var emittedText: String {
        (completedTextSegments.map(\.text) + [currentTextSegment.text]).joined()
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex
        while lhsIndex < lhs.endIndex, rhsIndex < rhs.endIndex, lhs[lhsIndex] == rhs[rhsIndex] {
            count += 1
            lhs.formIndex(after: &lhsIndex)
            rhs.formIndex(after: &rhsIndex)
        }
        return count
    }

    private static func suffixPrefixOverlapLength(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let maxLength = min(lhsChars.count, rhsChars.count)
        guard maxLength > 0 else { return 0 }
        var best = 0
        for length in 1...maxLength {
            if lhsChars[(lhsChars.count - length)..<lhsChars.count].elementsEqual(rhsChars[0..<length]) {
                best = length
            }
        }
        return best
    }

    mutating func orderKeyForToolCall(_ toolCallID: String) -> Double {
        if let existing = toolOrderKeys[toolCallID] {
            return existing
        }
        let orderKey = nextOrderKey
        toolOrderKeys[toolCallID] = orderKey
        if currentTextSegment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            completedTextSegments.append(currentTextSegment)
        }
        nextOrderKey += 1_000
        currentTextSegment = TextSegment(
            index: nextSegmentIndex,
            text: "",
            orderKey: nextOrderKey
        )
        nextSegmentIndex += 1
        nextOrderKey += 1_000
        return orderKey
    }

    func textSegmentsForFinalization() -> [TextSegment] {
        var segments = completedTextSegments
        if currentTextSegment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            segments.append(currentTextSegment)
        }
        return segments
    }

    func orderKeyIfKnown(forToolCallID toolCallID: String) -> Double? {
        toolOrderKeys[toolCallID]
    }

}

private extension ChatMessageBlock {
    nonisolated func normalizedForToolPresentation(assistantClientMessageID: UUID) -> ChatMessageBlock {
        guard let toolCallID else { return self }
        return ChatMessageBlock(
            id: id,
            anchor: anchor ?? .toolCall(toolCallID),
            kind: kind,
            text: text,
            toolName: toolName,
            toolCallID: toolCallID,
            parentToolCallID: toolCallID,
            parentBlockID: ChatStableBlockID.tool(messageID: assistantClientMessageID, toolCallID: toolCallID),
            nodeRole: .toolPresentation,
            attachments: attachments,
            knowledgeCards: knowledgeCards,
            taskCards: taskCards,
            pendingMemberToolCards: pendingMemberToolCards,
            locations: locations,
            routes: routes,
            events: events,
            healthCards: healthCards,
            structuredHealthCards: structuredHealthCards,
            sleepVisualization: sleepVisualization,
            workoutVisualization: workoutVisualization,
            captureMessageCard: captureMessageCard,
            smallTaskCard: smallTaskCard,
            deepThoughtCard: deepThoughtCard,
            status: status,
            revision: revision,
            orderKey: orderKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
