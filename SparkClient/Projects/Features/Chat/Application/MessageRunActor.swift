import Foundation

enum ChatRunEvent: Sendable {
    case assistantPartial(ChatAssistantPartialDelta, assistantClientMessageID: UUID)
    case richBlockReady(ChatMessageBlock, assistantClientMessageID: UUID)
    case toolSideEffect(
        ToolSideEffect,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    )
    case finalizeAssistantBlocks([ChatMessageBlock], assistantClientMessageID: UUID)
}

/// 工具异步任务（如结构化健康卡片抽取）向同一 actor 管道派发 UI 副作用。
protocol ChatSideEffectSink: Sendable {
    func emit(
        _ effect: ToolSideEffect,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    ) async
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
actor MessageRunActor: ChatSideEffectSink {
    private let repository: any ChatRepository
    private let pushOutbox: (@Sendable () async throws -> Void)?
    private let logger: Logger
    private var pendingPartials: [UUID: ChatAssistantPartialDelta] = [:]
    private var partialFlushTasks: [UUID: Task<Void, Never>] = [:]
    private var runStates: [UUID: AssistantRunState] = [:]
    private var lastAllocatedRevision: [UUID: Int64] = [:]
    private var writtenPendingPlaceholders: Set<String> = []
    private let partialFlushIntervalNs: UInt64 = 50_000_000

    init(
        repository: any ChatRepository,
        pushOutbox: (@Sendable () async throws -> Void)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.pushOutbox = pushOutbox
        self.logger = logger
    }

    func emit(
        _ effect: ToolSideEffect,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    ) async {
        _ = await apply(
            .toolSideEffect(
                effect,
                anchorToolCallID: anchorToolCallID,
                assistantClientMessageID: assistantClientMessageID
            )
        )
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
    @discardableResult
    func apply(_ event: ChatRunEvent) async -> Bool {
        // 根据事件类型分发处理
        switch event {
            
        // MARK: - 助手增量文本片段（流式输出：打字机效果）
        case .assistantPartial(let delta, let assistantClientMessageID):
            // 将增量文本片段加入队列，累积完整回答
            await enqueueAssistantPartial(delta, assistantClientMessageID: assistantClientMessageID)
            return true
            
        // MARK: - 富内容块就绪（图片/卡片/工具等非文本块）
        case .richBlockReady(let block, let assistantClientMessageID):
            let orderKeyOverride = await presentationOrderKey(
                for: block,
                assistantClientMessageID: assistantClientMessageID
            )
            let persisted = Self.databaseRichBlock(
                block,
                assistantClientMessageID: assistantClientMessageID,
                nextRevision: nextRevision(for: assistantClientMessageID, minimum: block.revision),
                orderKeyOverride: orderKeyOverride
            )
            let didApply = await repository.upsertMessageBlock(
                clientMessageID: assistantClientMessageID,
                block: persisted,
                markPendingForSync: block.status == .ready
            )
            if block.kind == .structuredHealthCards, block.status == .ready {
                let status = didApply ? "已写入" : "未生效"
                logger.info(
                    "结构化健康卡片 ready 块\(status)，blockID=\(persisted.id.uuidString), revision=\(persisted.revision), cards=\(persisted.structuredHealthCards?.totalCardCount ?? 0)",
                    module: .aiConfig
                )
                if didApply {
                    await requeueSentMessageForFullPush(
                        assistantClientMessageID: assistantClientMessageID,
                        reason: "structuredHealthCardsReady"
                    )
                }
            }
            return didApply

        case .toolSideEffect(let effect, let anchorToolCallID, let assistantClientMessageID):
            return await applyToolSideEffect(
                effect,
                anchorToolCallID: anchorToolCallID,
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
                        revision: nextRevision(for: assistantClientMessageID),  // 修订版本
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
                    block: finalizedAssistantBlock(
                        block,
                        assistantClientMessageID: assistantClientMessageID,
                        orderKeyOverride: orderKeyOverride
                    ),
                    markPendingForSync: true
                )
            }

            // 运行时流式已结束，消息不应继续暴露为 `.sending`。
            // 后续网络同步由 outbox 接管：先标记 `.pending`，push 成功后再变为 `.sent`。
            await repository.updateMessageDeliveryState(
                clientMessageID: assistantClientMessageID,
                state: .pending
            )
            
            // 7. 清理：消息已定稿，移除运行状态，释放内存
            let messagePrefix = assistantClientMessageID.uuidString + ":"
            runStates.removeValue(forKey: assistantClientMessageID)
            lastAllocatedRevision.removeValue(forKey: assistantClientMessageID)
            writtenPendingPlaceholders = writtenPendingPlaceholders.filter { !$0.hasPrefix(messagePrefix) }
            return true
        }
    }

    private func enqueueAssistantPartial(
        _ delta: ChatAssistantPartialDelta,
        assistantClientMessageID: UUID
    ) async {
        pendingPartials[assistantClientMessageID] = delta

        // 结构化健康卡片：在工具执行前同步落库 pending，避免 50ms 防抖晚于 ToolHub.publishPending。
        let shouldFlushStructuredHealthCardToolImmediately = delta.kind == .tool
            && delta.toolName == SparkToolName.generateStructuredHealthCard.rawValue
        if shouldFlushStructuredHealthCardToolImmediately {
            partialFlushTasks[assistantClientMessageID]?.cancel()
            partialFlushTasks[assistantClientMessageID] = nil
            await flushAssistantPartial(assistantClientMessageID: assistantClientMessageID)
            return
        }

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
        let revision = nextRevision(for: assistantClientMessageID)
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
                toolInvocationArguments: delta.toolInvocationArguments,
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

        if delta.toolName == SparkToolName.generateStructuredHealthCard.rawValue {
            let placeholderKey = "\(assistantClientMessageID.uuidString):\(toolCallID)"
            if writtenPendingPlaceholders.contains(placeholderKey) {
                return
            }
            let didApply = await upsertStructuredHealthCardPendingPlaceholder(
                assistantClientMessageID: assistantClientMessageID,
                toolCallID: toolCallID,
                toolOrderKey: toolOrderKey,
                toolRevision: revision,
                createdAt: now,
                updatedAt: now
            )
            if didApply {
                writtenPendingPlaceholders.insert(placeholderKey)
            }
        }
    }

    @discardableResult
    private func upsertStructuredHealthCardPendingPlaceholder(
        assistantClientMessageID: UUID,
        toolCallID: String,
        toolOrderKey: Double,
        toolRevision: Int64,
        createdAt: Date,
        updatedAt: Date
    ) async -> Bool {
        let presentationRevision = nextRevision(
            for: assistantClientMessageID,
            minimum: toolRevision + 1
        )
        let blockID = ChatStableBlockID.rich(
            messageID: assistantClientMessageID,
            toolCallID: toolCallID,
            kind: .structuredHealthCards
        )
        let didApply = await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: ChatMessageBlock(
                id: blockID,
                anchor: .toolCall(toolCallID),
                kind: .structuredHealthCards,
                toolCallID: toolCallID,
                parentToolCallID: toolCallID,
                parentBlockID: ChatStableBlockID.tool(
                    messageID: assistantClientMessageID,
                    toolCallID: toolCallID
                ),
                nodeRole: .toolPresentation,
                structuredHealthCards: .empty,
                status: .pending,
                revision: presentationRevision,
                orderKey: Self.presentationOrderKey(forToolOrderKey: toolOrderKey),
                createdAt: createdAt,
                updatedAt: updatedAt
            ),
            markPendingForSync: false
        )
        return didApply
    }

    func nextHealthResourceRefIndex(assistantClientMessageID: UUID) async -> Int {
        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        let count = messages.first?.blocks.filter { $0.kind == .healthResourceReference }.count ?? 0
        return count + 1
    }

    private func presentationOrderKey(
        for block: ChatMessageBlock,
        assistantClientMessageID: UUID
    ) async -> Double? {
        guard block.kind == .structuredHealthCards || block.kind == .healthResourceReference else {
            return block.orderKey
        }
        let toolCallID = block.parentToolCallID ?? block.toolCallID
        guard let toolCallID else { return block.orderKey }

        if let toolOrderKey = runStates[assistantClientMessageID]?.orderKeyIfKnown(forToolCallID: toolCallID) {
            return Self.presentationOrderKey(forToolOrderKey: toolOrderKey)
        }

        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        if let toolOrderKey = messages.first?.blocks.first(where: {
            $0.kind == .tool && $0.toolCallID == toolCallID
        })?.orderKey {
            return Self.presentationOrderKey(forToolOrderKey: toolOrderKey)
        }
        return block.orderKey
    }

    private static func presentationOrderKey(forToolOrderKey toolOrderKey: Double) -> Double {
        toolOrderKey + 100
    }

    /// 在助手消息时间线追加独立文本片段（用于异步工具失败提示等，不覆盖已有流式正文）。
    @discardableResult
    func appendTimelineNotice(
        _ text: String,
        assistantClientMessageID: UUID
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        guard let message = messages.first else { return false }

        let textSegmentCount = message.blocks.filter { $0.kind == .text }.count
        let maxTimelineOrderKey = message.blocks
            .filter { $0.nodeRole == .timeline }
            .compactMap(\.orderKey)
            .max() ?? 1_000
        let now = Date()
        let orderKey = max(maxTimelineOrderKey + 100, 3_100)

        return await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: ChatMessageBlock(
                id: ChatStableBlockID.textSegment(messageID: assistantClientMessageID, index: textSegmentCount),
                kind: .text,
                text: trimmed,
                nodeRole: .timeline,
                status: .ready,
                revision: Self.revision(now),
                orderKey: orderKey,
                createdAt: message.createdAt,
                updatedAt: now
            ),
            markPendingForSync: true
        )
    }

    /// Finalizes an interrupted run by keeping the notice inside the in-flight assistant message.
    func finalizeInterruptedAssistantMessage(
        statusCard: ChatAssistantStatusCardPayload,
        assistantClientMessageID: UUID
    ) async -> Bool {
        await flushAssistantPartial(assistantClientMessageID: assistantClientMessageID)
        let didAppendNotice = await appendTimelineStatusCard(
            statusCard,
            assistantClientMessageID: assistantClientMessageID
        )
        guard didAppendNotice else { return false }
        await repository.updateMessageDeliveryState(
            clientMessageID: assistantClientMessageID,
            state: .pending
        )

        let messagePrefix = assistantClientMessageID.uuidString + ":"
        runStates.removeValue(forKey: assistantClientMessageID)
        lastAllocatedRevision.removeValue(forKey: assistantClientMessageID)
        writtenPendingPlaceholders = writtenPendingPlaceholders.filter { !$0.hasPrefix(messagePrefix) }
        return true
    }

    @discardableResult
    private func appendTimelineStatusCard(
        _ statusCard: ChatAssistantStatusCardPayload,
        assistantClientMessageID: UUID
    ) async -> Bool {
        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        guard let message = messages.first else { return false }

        let maxTimelineOrderKey = message.blocks
            .filter { $0.nodeRole == .timeline }
            .compactMap(\.orderKey)
            .max() ?? 1_000
        let now = Date()
        let orderKey = max(maxTimelineOrderKey + 100, 3_100)

        return await repository.upsertMessageBlock(
            clientMessageID: assistantClientMessageID,
            block: ChatMessageBlock(
                id: ChatStableBlockID.rich(messageID: assistantClientMessageID, kind: .assistantStatusCard),
                kind: .assistantStatusCard,
                nodeRole: .timeline,
                assistantStatusCard: statusCard,
                status: .ready,
                revision: Self.revision(now),
                orderKey: orderKey,
                createdAt: message.createdAt,
                updatedAt: now
            ),
            markPendingForSync: true
        )
    }

    private func finalizedAssistantBlock(
        _ block: ChatMessageBlock,
        assistantClientMessageID: UUID,
        orderKeyOverride: Double? = nil
    ) -> ChatMessageBlock {
        let now = Date()
        let revision = nextRevision(for: assistantClientMessageID, minimum: block.revision + 1)
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
                toolInvocationArguments: block.toolInvocationArguments,
                toolCallID: block.toolCallID,
                nodeRole: .tool,
                status: .ready,
                revision: revision,
                orderKey: orderKeyOverride ?? block.orderKey ?? 2_000,
                createdAt: block.createdAt,
                updatedAt: now
            )
        default:
            return Self.databaseRichBlock(
                block,
                assistantClientMessageID: assistantClientMessageID,
                nextRevision: revision
            )
        }
    }

    private func nextRevision(for assistantClientMessageID: UUID, minimum: Int64 = 0) -> Int64 {
        let floor = max(minimum, Self.revision(Date()))
        let previous = lastAllocatedRevision[assistantClientMessageID] ?? 0
        let next = max(floor, previous + 1)
        lastAllocatedRevision[assistantClientMessageID] = next
        return next
    }

    private func requeueSentMessageForFullPush(
        assistantClientMessageID: UUID,
        reason: String
    ) async {
        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        guard let message = messages.first else {
            logger.warning(
                "结构化健康卡片 ready 后未找到父消息，无法重新入队，clientMessageID=\(assistantClientMessageID.uuidString)",
                module: .aiConfig
            )
            return
        }
        guard message.deliveryState == .sent else {
            logger.info(
                "结构化健康卡片 ready 后父消息暂不重入队，deliveryState=\(message.deliveryState.rawValue), reason=\(reason)",
                module: .aiConfig
            )
            return
        }
        await repository.updateMessageDeliveryState(
            clientMessageID: assistantClientMessageID,
            state: .pending
        )
        let reloaded = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID]).first
        let kinds = reloaded?.blocks.map(\.kind.rawValue).joined(separator: ", ") ?? "-"
        logger.info(
            "结构化健康卡片 ready 后父消息已重新入队整包上送，clientMessageID=\(assistantClientMessageID.uuidString), blockCount=\(reloaded?.blocks.count ?? 0), kinds=[\(kinds)], reason=\(reason)",
            module: .aiConfig
        )
    }

    @discardableResult
    private func applyToolSideEffect(
        _ effect: ToolSideEffect,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    ) async -> Bool {
        let normalizedAnchor = Self.normalizedToolCallID(anchorToolCallID)

        switch effect {
        case .healthResourceReference:
            let refIndex = await nextHealthResourceRefIndex(assistantClientMessageID: assistantClientMessageID)
            guard let blocks = ToolSideEffectBlockMapper.blocks(
                for: effect,
                assistantClientMessageID: assistantClientMessageID,
                normalizedAnchor: normalizedAnchor,
                healthResourceRefIndex: refIndex
            ) else {
                logger.warning("健康资料引用卡发布跳过：payload 无法编码", module: .aiConfig)
                return false
            }
            return await submitRichBlocks(blocks, assistantClientMessageID: assistantClientMessageID)
        case .knowledgeCards, .taskCards, .captureCard, .workoutVisualization, .sleepVisualization, .nutritionCards, .externalConnectorRichBlocks:
            guard let blocks = ToolSideEffectBlockMapper.blocks(
                for: effect,
                assistantClientMessageID: assistantClientMessageID,
                normalizedAnchor: normalizedAnchor
            ) else { return false }
            if case .workoutVisualization = effect, blocks.isEmpty {
                logger.warning("运动可视化卡片发布跳过：payload 无法编码", module: .aiConfig)
            }
            if case .sleepVisualization = effect, blocks.isEmpty {
                logger.warning("睡眠可视化卡片发布跳过：payload 无法编码", module: .aiConfig)
            }
            guard blocks.isEmpty == false else { return false }
            return await submitRichBlocks(blocks, assistantClientMessageID: assistantClientMessageID)
        case .structuredHealthCardsPending:
            guard let toolCallID = normalizedAnchor else { return false }
            let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
            let toolBlock = messages.first?.blocks.first { block in
                block.kind == .tool && block.toolCallID == toolCallID
            }
            let stateOrderKey = runStates[assistantClientMessageID]?.orderKeyIfKnown(forToolCallID: toolCallID)
            let toolOrderKey = toolBlock?.orderKey ?? stateOrderKey ?? 2_000
            let now = Date()
            return await upsertStructuredHealthCardPendingPlaceholder(
                assistantClientMessageID: assistantClientMessageID,
                toolCallID: toolCallID,
                toolOrderKey: toolOrderKey,
                toolRevision: nextRevision(for: assistantClientMessageID),
                createdAt: now,
                updatedAt: now
            )
        case .structuredHealthCardsReady(let blob):
            return await publishStructuredHealthCardsReady(
                blob: blob,
                anchorToolCallID: normalizedAnchor,
                assistantClientMessageID: assistantClientMessageID
            )
        case .structuredHealthCardsFailed(let message):
            return await submitRichBlocks(
                [
                    ChatMessageBlock(
                        anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                        kind: .structuredHealthCards,
                        toolCallID: normalizedAnchor,
                        parentToolCallID: normalizedAnchor,
                        structuredHealthCards: .failed(message: message ?? ""),
                        status: .failed
                    )
                ],
                assistantClientMessageID: assistantClientMessageID
            )
        case .timelineNotice(let text):
            await appendTimelineNotice(text, assistantClientMessageID: assistantClientMessageID)
            return true
        case .medicalRiskNotice(let payload):
            return await publishMedicalRiskNotice(
                payload: payload,
                anchorToolCallID: normalizedAnchor,
                assistantClientMessageID: assistantClientMessageID
            )
        }
    }

    @discardableResult
    private func publishMedicalRiskNotice(
        payload: ChatMedicalRiskNoticePayload,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    ) async -> Bool {
        let messages = await repository.loadMessages(clientMessageIDs: [assistantClientMessageID])
        if let existing = messages.first?.blocks.first(where: { $0.kind == .medicalRiskNotice }),
           case .medicalRiskNotice(let existingPayload) = existing.payload,
           payload.riskLevel <= existingPayload.riskLevel {
            return false
        }

        let block = ChatMessageBlock(
            anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
            kind: .medicalRiskNotice,
            toolCallID: anchorToolCallID,
            parentToolCallID: anchorToolCallID,
            medicalRiskNotice: payload,
            status: .ready
        )
        return await submitRichBlocks([block], assistantClientMessageID: assistantClientMessageID)
    }

    @discardableResult
    private func publishStructuredHealthCardsReady(
        blob: StructuredHealthCardsBlob,
        anchorToolCallID: String?,
        assistantClientMessageID: UUID
    ) async -> Bool {
        if blob.hasDisplayableCards == false {
            logger.warning(
                "结构化健康卡片 ready 发布跳过：抽取结果无卡片条目（examReports=\(blob.examReports.count), medicationPlans=\(blob.medicationPlans.count), medicineBoxes=\(blob.medicineBoxes.count), prescriptions=\(blob.prescriptions.count), medicalCases=\(blob.medicalCases.count)），assistantMessageClientID=\(assistantClientMessageID.uuidString)",
                module: .aiConfig
            )
            return await applyToolSideEffect(
                .structuredHealthCardsFailed(message: nil),
                anchorToolCallID: anchorToolCallID,
                assistantClientMessageID: assistantClientMessageID
            )
        }
        guard Self.isEncodable(blob) else {
            logger.warning("结构化健康卡片发布跳过：payload 无法编码", module: .aiConfig)
            return false
        }
        let didApply = await submitRichBlocks(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    parentToolCallID: anchorToolCallID,
                    structuredHealthCards: blob,
                    status: .ready
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
        guard didApply else {
            logger.warning(
                "结构化健康卡片 ready 写入未生效，跳过独立上送，assistantMessageClientID=\(assistantClientMessageID.uuidString)",
                module: .aiConfig
            )
            return false
        }
        logger.info(
            "结构化健康卡片 ready 已落库，cards=\(blob.totalCardCount)，assistantMessageClientID=\(assistantClientMessageID.uuidString)，准备独立上送 outbox",
            module: .aiConfig
        )
        if let pushOutbox {
            do {
                try await pushOutbox()
            } catch {
                logger.warning(
                    "结构化健康卡片 ready 后上送 outbox 失败：\(error.localizedDescription)",
                    module: .aiConfig
                )
            }
        }
        return true
    }

    @discardableResult
    private func submitRichBlocks(
        _ blocks: [ChatMessageBlock],
        assistantClientMessageID: UUID
    ) async -> Bool {
        var didApplyAny = false
        for block in blocks {
            let didApply = await apply(.richBlockReady(block, assistantClientMessageID: assistantClientMessageID))
            didApplyAny = didApplyAny || didApply
        }
        return didApplyAny
    }

    private static func isEncodable<T: Encodable>(_ value: T) -> Bool {
        (try? JSONEncoder.default.encode(value)) != nil
    }

    private static func normalizedToolCallID(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func databaseRichBlock(
        _ block: ChatMessageBlock,
        assistantClientMessageID: UUID,
        nextRevision: Int64,
        orderKeyOverride: Double? = nil
    ) -> ChatMessageBlock {
        let now = Date()
        let revision = nextRevision
        let stableID: UUID
        if block.kind == .healthResourceReference,
           let payload = block.healthResourceReferencePayload {
            stableID = ChatStableBlockID.healthResource(
                messageID: assistantClientMessageID,
                resourceType: payload.resourceType,
                resourceID: payload.resourceId,
                memberID: payload.memberId
            )
        } else if block.kind == .medicalRiskNotice {
            stableID = ChatStableBlockID.rich(messageID: assistantClientMessageID, kind: .medicalRiskNotice)
        } else if let toolCallID = block.toolCallID {
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
            orderKey: orderKeyOverride ?? block.orderKey ?? defaultOrderKey(for: block.kind)
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
        case .structuredHealthCards:
            // 须与父 tool 的 orderKey 绑定；无 tool 上下文时仅作兜底。
            return 2_100
        case .sleepVisualization, .workoutVisualization, .nutritionCards, .healthResourceReference,
                .captureCard, .knowledgeCards, .html, .taskCards,
                .pendingMemberToolCards:
            return 2_100
        case .medicalRiskNotice:
            return 2_900
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
    nonisolated var healthResourceReferencePayload: ChatHealthResourceReferencePayload? {
        guard case .healthResourceReference(let payload) = payload else { return nil }
        return payload
    }

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
            nutritionCards: nutritionCards,
            workoutVisualization: workoutVisualization,
            captureMessageCard: captureMessageCard,
            smallTaskCard: smallTaskCard,
            deepThoughtCard: deepThoughtCard,
            healthResourceReference: healthResourceReferencePayload,
            medicalRiskNotice: medicalRiskNotice,
            status: status,
            revision: revision,
            orderKey: orderKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
