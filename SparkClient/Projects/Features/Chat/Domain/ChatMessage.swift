import Foundation

nonisolated enum ChatMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant

    var runtimeRole: AIRuntimeRole {
        switch self {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}

nonisolated enum ChatMessageKind: String, Codable, Sendable {
    case text
    case tool
    case card
    case system
}

nonisolated enum ChatBlockAnchor: Codable, Equatable, Sendable {
    case messageStart
    case messageEnd
    case beforeBlock(UUID)
    case afterBlock(UUID)
    case toolCall(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum AnchorType: String, Codable {
        case messageStart
        case messageEnd
        case beforeBlock
        case afterBlock
        case toolCall
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(AnchorType.self, forKey: .type) {
        case .messageStart:
            self = .messageStart
        case .messageEnd:
            self = .messageEnd
        case .beforeBlock:
            self = .beforeBlock(try c.decode(UUID.self, forKey: .value))
        case .afterBlock:
            self = .afterBlock(try c.decode(UUID.self, forKey: .value))
        case .toolCall:
            self = .toolCall(try c.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .messageStart:
            try c.encode(AnchorType.messageStart, forKey: .type)
        case .messageEnd:
            try c.encode(AnchorType.messageEnd, forKey: .type)
        case .beforeBlock(let id):
            try c.encode(AnchorType.beforeBlock, forKey: .type)
            try c.encode(id, forKey: .value)
        case .afterBlock(let id):
            try c.encode(AnchorType.afterBlock, forKey: .type)
            try c.encode(id, forKey: .value)
        case .toolCall(let id):
            try c.encode(AnchorType.toolCall, forKey: .type)
            try c.encode(id, forKey: .value)
        }
    }
}

nonisolated enum ChatMessageBlockKind: String, Codable, Sendable {
    case text
    case deepThought
    case tool
    case imageGallery
    case fileAttachments
    case knowledgeCards
    case translatedText
    case mapRoute
    case events
    case healthCards
    case pendingMemberToolCards
    case structuredHealthCards
    case sleepVisualization
    case workoutVisualization
    case captureCard
    case html
    case smallTaskCard
    case taskCards
    case error
}

nonisolated struct ChatToolBlockPayload: Codable, Equatable, Sendable {
    let name: String?
    let content: String
}

nonisolated struct ChatMapRouteBlockPayload: Codable, Equatable, Sendable {
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
}

nonisolated struct ChatDeepThoughtCardPayload: Equatable, Codable, Sendable {
    var reasoningContent: String?
    var reasoningDurationMs: Int64?
    var reasoningExpanded: Bool
    var reasoningVisibility: ChatReasoningVisibility
}

nonisolated enum ChatMessageBlockPayload: Equatable, Sendable {
    case text(String)
    case deepThought(ChatDeepThoughtCardPayload)
    case tool(ChatToolBlockPayload)
    case imageGallery([ChatAttachment])
    case fileAttachments([ChatAttachment])
    case knowledgeCards([ChatKnowledgeCard])
    case translatedText(String)
    case mapRoute(ChatMapRouteBlockPayload)
    case events([ChatEventPayload])
    case healthCards([ChatHealthCardPayload])
    case pendingMemberToolCards([PendingMemberToolCard])
    case structuredHealthCards(StructuredHealthCardsBlob)
    case sleepVisualization(ChatHealthSleepModel)
    case workoutVisualization(ChatHealthWorkoutModel)
    case captureCard(ChatCaptureMessageCardPayload)
    case html(String)
    case smallTaskCard(ChatSmallTaskMessageCardPayload)
    case taskCards([TaskCard])
    case error(String)

    nonisolated var kind: ChatMessageBlockKind {
        switch self {
        case .text: return .text
        case .deepThought: return .deepThought
        case .tool: return .tool
        case .imageGallery: return .imageGallery
        case .fileAttachments: return .fileAttachments
        case .knowledgeCards: return .knowledgeCards
        case .translatedText: return .translatedText
        case .mapRoute: return .mapRoute
        case .events: return .events
        case .healthCards: return .healthCards
        case .pendingMemberToolCards: return .pendingMemberToolCards
        case .structuredHealthCards: return .structuredHealthCards
        case .sleepVisualization: return .sleepVisualization
        case .workoutVisualization: return .workoutVisualization
        case .captureCard: return .captureCard
        case .html: return .html
        case .smallTaskCard: return .smallTaskCard
        case .taskCards: return .taskCards
        case .error: return .error
        }
    }
}

nonisolated struct ChatMessageBlock: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let anchor: ChatBlockAnchor?
    let toolCallID: String?
    let payload: ChatMessageBlockPayload
    let createdAt: Date
    let updatedAt: Date

    nonisolated var kind: ChatMessageBlockKind { payload.kind }
    nonisolated var text: String? {
        switch payload {
        case .text(let text),
                .translatedText(let text),
                .html(let text),
                .error(let text):
            return text
        case .tool(let tool):
            return tool.content
        default:
            return nil
        }
    }
    nonisolated var toolName: String? {
        guard case .tool(let tool) = payload else { return nil }
        return tool.name
    }
    nonisolated var attachments: [ChatAttachment] {
        switch payload {
        case .imageGallery(let attachments), .fileAttachments(let attachments):
            return attachments
        default:
            return []
        }
    }
    nonisolated var knowledgeCards: [ChatKnowledgeCard] {
        guard case .knowledgeCards(let cards) = payload else { return [] }
        return cards
    }
    nonisolated var taskCards: [TaskCard] {
        guard case .taskCards(let cards) = payload else { return [] }
        return cards
    }
    nonisolated var pendingMemberToolCards: [PendingMemberToolCard] {
        guard case .pendingMemberToolCards(let cards) = payload else { return [] }
        return cards
    }
    nonisolated var locations: [ChatMapLocationPayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.locations
    }
    nonisolated var routes: [ChatRoutePayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.routes
    }
    nonisolated var events: [ChatEventPayload] {
        guard case .events(let events) = payload else { return [] }
        return events
    }
    nonisolated var healthCards: [ChatHealthCardPayload] {
        guard case .healthCards(let cards) = payload else { return [] }
        return cards
    }
    nonisolated var structuredHealthCards: StructuredHealthCardsBlob? {
        guard case .structuredHealthCards(let blob) = payload else { return nil }
        return blob
    }
    nonisolated var sleepVisualization: ChatHealthSleepModel? {
        guard case .sleepVisualization(let model) = payload else { return nil }
        return model
    }
    nonisolated var workoutVisualization: ChatHealthWorkoutModel? {
        guard case .workoutVisualization(let model) = payload else { return nil }
        return model
    }
    nonisolated var captureMessageCard: ChatCaptureMessageCardPayload? {
        guard case .captureCard(let card) = payload else { return nil }
        return card
    }
    nonisolated var smallTaskCard: ChatSmallTaskMessageCardPayload? {
        guard case .smallTaskCard(let card) = payload else { return nil }
        return card
    }
    nonisolated var deepThoughtCard: ChatDeepThoughtCardPayload? {
        guard case .deepThought(let card) = payload else { return nil }
        return card
    }

    nonisolated init(
        id: UUID = UUID(),
        anchor: ChatBlockAnchor? = nil,
        kind: ChatMessageBlockKind,
        text: String? = nil,
        toolName: String? = nil,
        toolCallID: String? = nil,
        attachments: [ChatAttachment] = [],
        knowledgeCards: [ChatKnowledgeCard] = [],
        taskCards: [TaskCard] = [],
        pendingMemberToolCards: [PendingMemberToolCard] = [],
        locations: [ChatMapLocationPayload] = [],
        routes: [ChatRoutePayload] = [],
        events: [ChatEventPayload] = [],
        healthCards: [ChatHealthCardPayload] = [],
        structuredHealthCards: StructuredHealthCardsBlob? = nil,
        sleepVisualization: ChatHealthSleepModel? = nil,
        workoutVisualization: ChatHealthWorkoutModel? = nil,
        captureMessageCard: ChatCaptureMessageCardPayload? = nil,
        smallTaskCard: ChatSmallTaskMessageCardPayload? = nil,
        deepThoughtCard: ChatDeepThoughtCardPayload? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.anchor = anchor
        self.toolCallID = toolCallID
        self.payload = Self.makePayload(
            kind: kind,
            text: text,
            toolName: toolName,
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
            deepThoughtCard: deepThoughtCard
        )
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case anchor
        case kind
        case text
        case toolName
        case toolCallID
        case attachments
        case knowledgeCards
        case taskCards
        case pendingMemberToolCards
        case locations
        case routes
        case events
        case healthCards
        case structuredHealthCards
        case sleepVisualization
        case workoutVisualization
        case captureMessageCard
        case smallTaskCard
        case deepThoughtCard
        case createdAt
        case updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let anchor = try c.decodeIfPresent(ChatBlockAnchor.self, forKey: .anchor)
        let kind = try c.decode(ChatMessageBlockKind.self, forKey: .kind)
        let text = try c.decodeIfPresent(String.self, forKey: .text)
        let toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        let toolCallID = try c.decodeIfPresent(String.self, forKey: .toolCallID)
        let attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        let knowledgeCards = try c.decodeIfPresent([ChatKnowledgeCard].self, forKey: .knowledgeCards) ?? []
        let taskCards = try c.decodeIfPresent([TaskCard].self, forKey: .taskCards) ?? []
        let pendingMemberToolCards = try c.decodeIfPresent([PendingMemberToolCard].self, forKey: .pendingMemberToolCards) ?? []
        let locations = try c.decodeIfPresent([ChatMapLocationPayload].self, forKey: .locations) ?? []
        let routes = try c.decodeIfPresent([ChatRoutePayload].self, forKey: .routes) ?? []
        let events = try c.decodeIfPresent([ChatEventPayload].self, forKey: .events) ?? []
        let healthCards = try c.decodeIfPresent([ChatHealthCardPayload].self, forKey: .healthCards) ?? []
        let structuredHealthCards = try c.decodeIfPresent(StructuredHealthCardsBlob.self, forKey: .structuredHealthCards)
        let sleepVisualization = try c.decodeIfPresent(ChatHealthSleepModel.self, forKey: .sleepVisualization)
        let workoutVisualization = try c.decodeIfPresent(ChatHealthWorkoutModel.self, forKey: .workoutVisualization)
        let captureMessageCard = try c.decodeIfPresent(ChatCaptureMessageCardPayload.self, forKey: .captureMessageCard)
        let smallTaskCard = try c.decodeIfPresent(ChatSmallTaskMessageCardPayload.self, forKey: .smallTaskCard)
        let deepThoughtCard = try c.decodeIfPresent(ChatDeepThoughtCardPayload.self, forKey: .deepThoughtCard)
        let createdAt = try c.decode(Date.self, forKey: .createdAt)
        let updatedAt = try c.decode(Date.self, forKey: .updatedAt)

        self.init(
            id: id,
            anchor: anchor,
            kind: kind,
            text: text,
            toolName: toolName,
            toolCallID: toolCallID,
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
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(anchor, forKey: .anchor)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
        if attachments.isEmpty == false { try c.encode(attachments, forKey: .attachments) }
        if knowledgeCards.isEmpty == false { try c.encode(knowledgeCards, forKey: .knowledgeCards) }
        if taskCards.isEmpty == false { try c.encode(taskCards, forKey: .taskCards) }
        if pendingMemberToolCards.isEmpty == false { try c.encode(pendingMemberToolCards, forKey: .pendingMemberToolCards) }
        if locations.isEmpty == false { try c.encode(locations, forKey: .locations) }
        if routes.isEmpty == false { try c.encode(routes, forKey: .routes) }
        if events.isEmpty == false { try c.encode(events, forKey: .events) }
        if healthCards.isEmpty == false { try c.encode(healthCards, forKey: .healthCards) }
        try c.encodeIfPresent(structuredHealthCards, forKey: .structuredHealthCards)
        try c.encodeIfPresent(sleepVisualization, forKey: .sleepVisualization)
        try c.encodeIfPresent(workoutVisualization, forKey: .workoutVisualization)
        try c.encodeIfPresent(captureMessageCard, forKey: .captureMessageCard)
        try c.encodeIfPresent(smallTaskCard, forKey: .smallTaskCard)
        try c.encodeIfPresent(deepThoughtCard, forKey: .deepThoughtCard)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private nonisolated static func makePayload(
        kind: ChatMessageBlockKind,
        text: String?,
        toolName: String?,
        attachments: [ChatAttachment],
        knowledgeCards: [ChatKnowledgeCard],
        taskCards: [TaskCard],
        pendingMemberToolCards: [PendingMemberToolCard],
        locations: [ChatMapLocationPayload],
        routes: [ChatRoutePayload],
        events: [ChatEventPayload],
        healthCards: [ChatHealthCardPayload],
        structuredHealthCards: StructuredHealthCardsBlob?,
        sleepVisualization: ChatHealthSleepModel?,
        workoutVisualization: ChatHealthWorkoutModel?,
        captureMessageCard: ChatCaptureMessageCardPayload?,
        smallTaskCard: ChatSmallTaskMessageCardPayload?,
        deepThoughtCard: ChatDeepThoughtCardPayload?
    ) -> ChatMessageBlockPayload {
        switch kind {
        case .text:
            return .text(text ?? "")
        case .deepThought:
            return .deepThought(
                deepThoughtCard ?? ChatDeepThoughtCardPayload(
                    reasoningContent: text,
                    reasoningDurationMs: nil,
                    reasoningExpanded: false,
                    reasoningVisibility: .full
                )
            )
        case .tool:
            return .tool(.init(name: toolName, content: text ?? ""))
        case .imageGallery:
            return .imageGallery(attachments)
        case .fileAttachments:
            return .fileAttachments(attachments)
        case .knowledgeCards:
            return .knowledgeCards(knowledgeCards)
        case .translatedText:
            return .translatedText(text ?? "")
        case .mapRoute:
            return .mapRoute(.init(locations: locations, routes: routes))
        case .events:
            return .events(events)
        case .healthCards:
            return .healthCards(healthCards)
        case .pendingMemberToolCards:
            return .pendingMemberToolCards(pendingMemberToolCards)
        case .structuredHealthCards:
            return .structuredHealthCards(structuredHealthCards ?? .empty)
        case .sleepVisualization:
            guard let sleepVisualization else {
                preconditionFailure("Missing sleep visualization payload for sleepVisualization block")
            }
            return .sleepVisualization(sleepVisualization)
        case .workoutVisualization:
            guard let workoutVisualization else {
                preconditionFailure("Missing workout visualization payload for workoutVisualization block")
            }
            return .workoutVisualization(workoutVisualization)
        case .captureCard:
            guard let captureMessageCard else {
                preconditionFailure("Missing capture payload for captureCard block")
            }
            return .captureCard(captureMessageCard)
        case .html:
            return .html(text ?? "")
        case .smallTaskCard:
            guard let smallTaskCard else {
                preconditionFailure("Missing small task payload for smallTaskCard block")
            }
            return .smallTaskCard(smallTaskCard)
        case .taskCards:
            return .taskCards(taskCards)
        case .error:
            return .error(text ?? "")
        }
    }
}

extension ChatMessageBlock {
    /// Payload-backed round-trip for ``ChatMessageBlockDTO`` / ``ChatMessageBlockBuilder``.
    fileprivate nonisolated init(id: UUID, anchor: ChatBlockAnchor?, toolCallID: String?, payload: ChatMessageBlockPayload, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.anchor = anchor
        self.toolCallID = toolCallID
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Merge semantics used by ``ChatMessageBlockBuilder`` (stable `id` / `createdAt`).
    fileprivate nonisolated static func mergeReplacementPreservingIdentity(original: ChatMessageBlock, incoming: ChatMessageBlock) -> ChatMessageBlock {
        ChatMessageBlock(
            id: original.id,
            anchor: incoming.anchor,
            kind: incoming.kind,
            text: incoming.text,
            toolName: incoming.toolName,
            toolCallID: incoming.toolCallID,
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

    nonisolated func toDTO() -> ChatMessageBlockDTO {
        ChatMessageBlockDTO(
            id: id,
            anchor: anchor,
            toolCallID: toolCallID,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// 消息块合并用的值快照（`Sendable`），与 ``ChatMessageBlock`` 分离，供 ``ChatMessageBlockBuilder`` 在 `nonisolated` 上下文中处理。
nonisolated struct ChatMessageBlockDTO: Identifiable, Sendable, Equatable {
    let id: UUID
    let anchor: ChatBlockAnchor?
    let toolCallID: String?
    let payload: ChatMessageBlockPayload
    let createdAt: Date
    let updatedAt: Date
}

extension ChatMessageBlockDTO {
    /// 还原为聊天 UI / 存储模型（`ChatMessageBlock` 为 `Sendable`，可在任意隔离域调用）。
    nonisolated func toUIModel() -> ChatMessageBlock {
        ChatMessageBlock(id: id, anchor: anchor, toolCallID: toolCallID, payload: payload, createdAt: createdAt, updatedAt: updatedAt)
    }

    fileprivate nonisolated var kind: ChatMessageBlockKind { payload.kind }

    fileprivate nonisolated var asBlock: ChatMessageBlock { toUIModel() }
}

nonisolated struct ChatMessageStorageEnvelope: Codable, Equatable, Sendable {
    let blocks: [ChatMessageBlock]
}

nonisolated struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let threadID: UUID
    let role: ChatMessageRole
    let blocks: [ChatMessageBlock]
    let clientMessageID: UUID
    let serverMessageID: String?
    let deliveryState: ChatDeliveryState
    let createdAt: Date
    let serverUpdatedAt: Date?
    let isTombstone: Bool
    let modelName: String?

    nonisolated init(
        id: UUID = UUID(),
        threadID: UUID,
        role: ChatMessageRole,
        blocks: [ChatMessageBlock],
        clientMessageID: UUID = UUID(),
        serverMessageID: String? = nil,
        deliveryState: ChatDeliveryState = .pending,
        createdAt: Date = Date(),
        serverUpdatedAt: Date? = nil,
        isTombstone: Bool = false,
        modelName: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.blocks = blocks
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.deliveryState = deliveryState
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.isTombstone = isTombstone
        self.modelName = modelName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case role
        case blocks
        case clientMessageID
        case serverMessageID
        case deliveryState
        case createdAt
        case serverUpdatedAt
        case isTombstone
        case modelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        threadID = try c.decode(UUID.self, forKey: .threadID)
        role = try c.decode(ChatMessageRole.self, forKey: .role)
        blocks = try c.decode([ChatMessageBlock].self, forKey: .blocks)
        clientMessageID = try c.decode(UUID.self, forKey: .clientMessageID)
        serverMessageID = try c.decodeIfPresent(String.self, forKey: .serverMessageID)
        deliveryState = try c.decode(ChatDeliveryState.self, forKey: .deliveryState)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        serverUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
        isTombstone = try c.decodeIfPresent(Bool.self, forKey: .isTombstone) ?? false
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(role, forKey: .role)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(clientMessageID, forKey: .clientMessageID)
        try c.encodeIfPresent(serverMessageID, forKey: .serverMessageID)
        try c.encode(deliveryState, forKey: .deliveryState)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
        try c.encode(isTombstone, forKey: .isTombstone)
        try c.encodeIfPresent(modelName, forKey: .modelName)
    }

}

/// 聊天消息块构建器
/// 核心职责：
/// 1. 流式消息合并（增量更新不闪屏）
/// 2. 块去重（避免重复卡片/附件）
/// 3. 锚点定位（把卡片插到对应工具调用下方）
/// 4. 结构归一化（最终展示顺序稳定）
///
/// 合并逻辑仅处理 ``ChatMessageBlockDTO``（`Sendable` 值快照）；展示模型在边界通过 ``ChatMessageBlock/toDTO()`` 与 ``ChatMessageBlockDTO/toUIModel()`` 转换。
nonisolated enum ChatMessageBlockBuilder {

    // MARK: - 富文本块合并（流式增量更新）— DTO 核心 API
    /// 合并增量富文本块（用于流式打字机效果）
    /// 规则：能替换则替换 → 能按锚点插入则插入 → 否则追加
    nonisolated static func mergeRichBlocks(
        existing: [ChatMessageBlockDTO],
        incoming: [ChatMessageBlockDTO]
    ) -> [ChatMessageBlockDTO] {
        var result = existing
        for block in incoming {
            if let index = replacementIndex(in: result, for: block) {
                result[index] = mergedReplacement(original: result[index], incoming: block)
            } else if let insertIndex = anchoredInsertIndex(in: result, for: block) {
                result.insert(block, at: insertIndex)
            } else {
                result.append(block)
            }
        }
        return stabilizeToolAnchoredPresentationBlockOrder(deduplicated(result))
    }

    /// 便捷：直接合并 ``ChatMessageBlock``（内部走 DTO，调用方无需手写映射）。
    nonisolated static func mergeRichBlocks(
        existingBlocks: [ChatMessageBlock],
        incomingBlocks: [ChatMessageBlock]
    ) -> [ChatMessageBlock] {
        mergeRichBlocks(
            existing: existingBlocks.map { $0.toDTO() },
            incoming: incomingBlocks.map { $0.toDTO() }
        ).map { $0.toUIModel() }
    }

    // MARK: - 流式结束最终归一化
    /// 流式渲染完成后，最终整理一次块顺序
    /// 确保所有卡片都贴在对应 toolCall 后面，和睡眠卡逻辑一致
    nonisolated static func finalizeStreamingPresentationBlocks(_ blocks: [ChatMessageBlockDTO]) -> [ChatMessageBlockDTO] {
        stabilizeToolAnchoredPresentationBlockOrder(blocks)
    }

    nonisolated static func finalizeStreamingPresentationBlocks(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        finalizeStreamingPresentationBlocks(blocks.map { $0.toDTO() }).map { $0.toUIModel() }
    }

    // MARK: - 组合块（去重 + 排序）
    /// 组合并归一化消息块：去重 + 排序
    nonisolated static func composeBlocks(_ blocks: [ChatMessageBlockDTO]) -> [ChatMessageBlockDTO] {
        stabilizeToolAnchoredPresentationBlockOrder(deduplicated(blocks))
    }

    nonisolated static func composeBlocks(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        composeBlocks(blocks.map { $0.toDTO() }).map { $0.toUIModel() }
    }

    // MARK: - 结构合并（保留文本/工具/错误，合并展示块）
    /// 合并消息结构：
    /// 保留核心结构块（文本/深度思考/工具/错误）
    /// 追加展示类块（卡片、可视化等）
    nonisolated static func merge(
        existing: [ChatMessageBlockDTO],
        incoming: [ChatMessageBlockDTO]
    ) -> [ChatMessageBlockDTO] {
        let composed = composeBlocks(incoming)
        guard !existing.isEmpty else { return composed }

        let structuralKinds: Set<ChatMessageBlockKind> = [.text, .deepThought, .tool, .error]
        var merged = existing.filter { structuralKinds.contains($0.kind) }
        let toolIDs = Set(merged.compactMap(\.toolCallID))

        for block in composed {
            if !structuralKinds.contains(block.kind) {
                merged.append(block)
            } else if block.kind == .tool,
                      let toolCallID = block.toolCallID,
                      !toolIDs.contains(toolCallID) {
                merged.append(block)
            }
        }

        return stabilizeToolAnchoredPresentationBlockOrder(merged)
    }

    nonisolated static func merge(
        existingBlocks: [ChatMessageBlock],
        incomingBlocks: [ChatMessageBlock]
    ) -> [ChatMessageBlock] {
        merge(
            existing: existingBlocks.map { $0.toDTO() },
            incoming: incomingBlocks.map { $0.toDTO() }
        ).map { $0.toUIModel() }
    }

    // MARK: - 查找可替换的块索引
    nonisolated private static func replacementIndex(
        in blocks: [ChatMessageBlockDTO],
        for incoming: ChatMessageBlockDTO
    ) -> Int? {
        let incomingBlock = incoming.asBlock

        if let firstCard = incomingBlock.pendingMemberToolCards.first {
            return blocks.firstIndex { block in
                block.kind == .pendingMemberToolCards
                    && block.asBlock.pendingMemberToolCards.contains(where: { $0.id == firstCard.id })
            }
        }

        if incoming.kind == .structuredHealthCards
            || incoming.kind == .sleepVisualization
            || incoming.kind == .workoutVisualization
            || incoming.kind == .captureCard
            || incoming.kind == .knowledgeCards
            || incoming.kind == .html {
            return blocks.firstIndex {
                $0.kind == incoming.kind
                    && $0.toolCallID == incoming.toolCallID
                    && $0.anchor == incoming.anchor
            }
        }

        if let toolCallID = incoming.toolCallID {
            return blocks.firstIndex {
                $0.kind == incoming.kind
                    && $0.toolCallID == toolCallID
                    && $0.anchor == incoming.anchor
            }
        }

        return nil
    }

    // MARK: - 根据锚点获取插入位置
    nonisolated private static func anchoredInsertIndex(
        in blocks: [ChatMessageBlockDTO],
        for incoming: ChatMessageBlockDTO
    ) -> Int? {
        switch incoming.anchor {
        case .beforeBlock(let id):
            return blocks.firstIndex(where: { $0.id == id })
        case .afterBlock(let id):
            return blocks.firstIndex(where: { $0.id == id }).map { $0 + 1 }
        case .toolCall(let toolCallID):
            return blocks.lastIndex(where: { $0.toolCallID == toolCallID }).map { $0 + 1 }
        case .messageStart:
            return 0
        case .messageEnd, .none:
            return nil
        }
    }

    // MARK: - 合并替换块
    nonisolated private static func mergedReplacement(
        original: ChatMessageBlockDTO,
        incoming: ChatMessageBlockDTO
    ) -> ChatMessageBlockDTO {
        ChatMessageBlock.mergeReplacementPreservingIdentity(original: original.asBlock, incoming: incoming.asBlock).toDTO()
    }

    // MARK: - 去重
    nonisolated private static func deduplicated(_ blocks: [ChatMessageBlockDTO]) -> [ChatMessageBlockDTO] {
        var seenAttachmentIDs: Set<UUID> = []
        var seenPendingCardIDs: Set<UUID> = []
        var seenTaskCardIDs: Set<Int> = []
        var out: [ChatMessageBlockDTO] = []

        for dto in blocks {
            let block = dto.asBlock
            switch block.kind {
            case .pendingMemberToolCards:
                let ids = block.pendingMemberToolCards.map(\.id)
                guard ids.allSatisfy({ seenPendingCardIDs.insert($0).inserted }) else { continue }
            case .taskCards:
                let ids = block.taskCards.map(\.id)
                guard ids.allSatisfy({ seenTaskCardIDs.insert($0).inserted }) else { continue }
            case .captureCard, .structuredHealthCards, .sleepVisualization, .workoutVisualization, .knowledgeCards, .html:
                if out.contains(where: { $0.kind == dto.kind && $0 == dto }) {
                    continue
                }
            default:
                break
            }

            if !block.attachments.isEmpty {
                let allNew = block.attachments.allSatisfy { seenAttachmentIDs.insert($0.id).inserted }
                if !allNew { continue }
            }

            out.append(dto)
        }
        return out
    }

    // MARK: - 稳定工具锚点顺序（核心排序）
    nonisolated private static func stabilizeToolAnchoredPresentationBlockOrder(_ blocks: [ChatMessageBlockDTO]) -> [ChatMessageBlockDTO] {
        guard blocks.count > 1 else { return blocks }
        var reordered = blocks

        for _ in 0..<32 {
            var didChange = false

            let blockIDsToRelocate: [UUID] = reordered.compactMap { dto in
                guard dto.kind != .tool, case .toolCall = dto.anchor else { return nil }
                return dto.id
            }

            for blockID in blockIDsToRelocate {
                guard let currentIndex = reordered.firstIndex(where: { $0.id == blockID }) else { continue }
                let dto = reordered[currentIndex]

                guard case .toolCall(let toolCallID) = dto.anchor, !toolCallID.isEmpty else { continue }
                guard let toolIndex = reordered.lastIndex(where: {
                    $0.kind == .tool && $0.toolCallID == toolCallID
                }) else { continue }

                let targetIndex = toolIndex + 1
                if currentIndex == targetIndex { continue }

                let moving = reordered.remove(at: currentIndex)
                let adjustedTarget = currentIndex < targetIndex ? max(0, targetIndex - 1) : targetIndex
                reordered.insert(moving, at: min(adjustedTarget, reordered.count))

                didChange = true
                break
            }

            if !didChange { break }
        }

        return reordered
    }
}

private extension ChatBlockAnchor {
    var blockID: UUID? {
        switch self {
        case .beforeBlock(let id), .afterBlock(let id):
            return id
        case .messageStart, .messageEnd, .toolCall:
            return nil
        }
    }
}

extension ChatMessage {
    /// 与指定 `toolCallID` 关联的业务展示块（用于工具详情 Sheet；不含工具行/文本/思考/错误）。
    nonisolated func chatBlocksLinkedToToolCall(_ toolCallID: String?, excludingBlockId: UUID) -> [ChatMessageBlock] {
        guard let toolCallID, toolCallID.isEmpty == false else { return [] }
        let kinds: Set<ChatMessageBlockKind> = [
            .taskCards,
            .pendingMemberToolCards,
            .structuredHealthCards,
            .sleepVisualization,
            .workoutVisualization,
            .knowledgeCards,
            .captureCard,
            .html,
            .smallTaskCard,
            .healthCards,
            .events,
            .mapRoute
        ]
        return blocks.filter {
            $0.id != excludingBlockId
                && $0.toolCallID == toolCallID
                && kinds.contains($0.kind)
        }
    }

    /// 由工具消息块构造全局工具详情 Sheet 的载荷（含同 `toolCallID` 关联块 id）。
    nonisolated func makeToolPreviewPrompt(forToolBlock toolBlock: ChatMessageBlock) -> ToolPreviewPrompt? {
        guard case .tool(let t) = toolBlock.payload else { return nil }
        let related = chatBlocksLinkedToToolCall(toolBlock.toolCallID, excludingBlockId: toolBlock.id)
        return ToolPreviewPrompt(
            toolName: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: t.name),
            toolContent: t.content,
            toolCallID: toolBlock.toolCallID,
            threadID: threadID,
            sourceClientMessageID: clientMessageID,
            relatedBlockIDs: related.map(\.id)
        )
    }

    nonisolated static func shouldPreferRemoteUserImageSyncData(local: ChatMessage, remote: ChatMessage) -> Bool {
        guard local.clientMessageID == remote.clientMessageID else { return false }
        guard local.role == .user, remote.role == .user else { return false }
        let localScore = userImageRichAttachmentScore(local)
        let remoteScore = userImageRichAttachmentScore(remote)
        return remoteScore > localScore
    }

    nonisolated private static func userImageRichAttachmentScore(_ message: ChatMessage) -> Int {
        var score = 0
        let attachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
        for attachment in attachments where attachment.isChatImageLike {
            if attachment.effectiveHTTPSImageDownloadURL != nil {
                score += 8
                continue
            }
            var piece = 0
            if let k = attachment.fullCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), k.isEmpty == false { piece += 2 }
            if let md5 = attachment.fileMd5?.trimmingCharacters(in: .whitespacesAndNewlines), md5.isEmpty == false { piece += 2 }
            if let fid = attachment.fileId, fid > 0 { piece += 2 }
            if let t = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines), t.isEmpty == false { piece += 1 }
            score += piece
        }
        return score
    }
}

struct ChatThreadSnapshot: Sendable {
    let thread: ChatThread
    let messages: [ChatMessage]
}

struct ChatThreadListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let thread: ChatThread
    let latestMessagePreview: String
    let latestMessageAt: Date
    let unreadCount: Int
    let latestListImageAttachment: ChatAttachment?
}

enum ChatFeatureError: LocalizedError {
    case emptyInput
    case threadNotFound
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入消息后再发送。"
        case .threadNotFound:
            return "对话线程不存在，请重新创建。"
        case .syncFailed(let reason):
            return "同步失败：\(reason)"
        }
    }
}
