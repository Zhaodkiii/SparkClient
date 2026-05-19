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


    private enum AnchorType: String, Codable {
        case messageStart
        case messageEnd
        case beforeBlock
        case afterBlock
        case toolCall
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        switch try c.decode(AnchorType.self, forKey: .key("type")) {
        case .messageStart:
            self = .messageStart
        case .messageEnd:
            self = .messageEnd
        case .beforeBlock:
            self = .beforeBlock(try c.decode(UUID.self, forKey: .key("value")))
        case .afterBlock:
            self = .afterBlock(try c.decode(UUID.self, forKey: .key("value")))
        case .toolCall:
            self = .toolCall(try c.decode(String.self, forKey: .key("value")))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        switch self {
        case .messageStart:
            try c.encode(AnchorType.messageStart, forKey: .key("type"))
        case .messageEnd:
            try c.encode(AnchorType.messageEnd, forKey: .key("type"))
        case .beforeBlock(let id):
            try c.encode(AnchorType.beforeBlock, forKey: .key("type"))
            try c.encode(id, forKey: .key("value"))
        case .afterBlock(let id):
            try c.encode(AnchorType.afterBlock, forKey: .key("type"))
            try c.encode(id, forKey: .key("value"))
        case .toolCall(let id):
            try c.encode(AnchorType.toolCall, forKey: .key("type"))
            try c.encode(id, forKey: .key("value"))
        }
    }
}

/// 聊天消息块类型枚举
/// 用于标识聊天消息中不同展示样式、功能模块的块类型
nonisolated enum ChatMessageBlockKind: String, Codable, Sendable {
    /// 纯文本内容块
    case text
    /// 深度思考/AI 推理过程块
    case deepThought
    /// 工具调用块（如函数调用、插件执行）
    case tool
    /// 图片画廊/多图展示块
    case imageGallery
    /// 文件附件块
    case fileAttachments
    /// 知识卡片块
    case knowledgeCards
    /// 翻译文本块
    case translatedText
    /// 地图路线块
    case mapRoute
    /// 日程/事件块
    case events
    /// 健康数据卡片块
    case healthCards
    /// 待处理成员工具卡片块
    case pendingMemberToolCards
    /// 结构化健康卡片块
    case structuredHealthCards
    /// 睡眠可视化展示块
    case sleepVisualization
    /// 运动/健身可视化展示块
    case workoutVisualization
    /// 快速捕获卡片块
    case captureCard
    /// HTML 富内容块
    case html
    /// 小型任务卡片块
    case smallTaskCard
    /// 任务列表卡片块
    case taskCards
    /// 错误信息块
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

/// 聊天消息块：聊天界面中独立的内容单元（文本/卡片/附件/工具等）
/// 遵循非孤立、唯一标识、可序列化、可比较、线程安全协议
nonisolated struct ChatMessageBlock: Identifiable, Codable, Equatable, Sendable {
    // MARK: - 基础属性
    /// 唯一标识
    let id: UUID
    /// 块锚点（定位/关联标记，可选）
    let anchor: ChatBlockAnchor?
    /// 工具调用 ID（可选）
    let toolCallId: String?
    /// 消息块负载数据（核心内容）
    let payload: ChatMessageBlockPayload
    /// 创建时间
    let createdAt: Date
    /// 更新时间
    let updatedAt: Date

    // MARK: - 计算属性（快捷访问 payload 内容）
    /// 工具调用 ID（兼容命名）
    nonisolated var toolCallID: String? { toolCallId }
    
    /// 消息块类型（从负载中自动获取）
    nonisolated var kind: ChatMessageBlockKind { payload.kind }
    
    /// 文本内容：提取文本/翻译文本/HTML/错误/工具中的文本
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
    
    /// 工具名称：仅工具类型块有效
    nonisolated var toolName: String? {
        guard case .tool(let tool) = payload else { return nil }
        return tool.name
    }
    
    /// 附件列表：图片画廊/文件附件类型有效
    nonisolated var attachments: [ChatAttachment] {
        switch payload {
        case .imageGallery(let attachments), .fileAttachments(let attachments):
            return attachments
        default:
            return []
        }
    }
    
    /// 知识卡片列表
    nonisolated var knowledgeCards: [ChatKnowledgeCard] {
        guard case .knowledgeCards(let cards) = payload else { return [] }
        return cards
    }
    
    /// 任务卡片列表
    nonisolated var taskCards: [TaskCard] {
        guard case .taskCards(let cards) = payload else { return [] }
        return cards
    }
    
    /// 待处理成员工具卡片列表
    nonisolated var pendingMemberToolCards: [PendingMemberToolCard] {
        guard case .pendingMemberToolCards(let cards) = payload else { return [] }
        return cards
    }
    
    /// 地图位置列表
    nonisolated var locations: [ChatMapLocationPayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.locations
    }
    
    /// 地图路线列表
    nonisolated var routes: [ChatRoutePayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.routes
    }
    
    /// 事件列表
    nonisolated var events: [ChatEventPayload] {
        guard case .events(let events) = payload else { return [] }
        return events
    }
    
    /// 健康卡片列表
    nonisolated var healthCards: [ChatHealthCardPayload] {
        guard case .healthCards(let cards) = payload else { return [] }
        return cards
    }
    
    /// 结构化健康卡片数据
    nonisolated var structuredHealthCards: StructuredHealthCardsBlob? {
        guard case .structuredHealthCards(let blob) = payload else { return nil }
        return blob
    }
    
    /// 睡眠可视化模型
    nonisolated var sleepVisualization: ChatHealthSleepModel? {
        guard case .sleepVisualization(let model) = payload else { return nil }
        return model
    }
    
    /// 运动可视化模型
    nonisolated var workoutVisualization: ChatHealthWorkoutModel? {
        guard case .workoutVisualization(let model) = payload else { return nil }
        return model
    }
    
    /// 捕获消息卡片数据
    nonisolated var captureMessageCard: ChatCaptureMessageCardPayload? {
        guard case .captureCard(let card) = payload else { return nil }
        return card
    }
    
    /// 小型任务卡片数据
    nonisolated var smallTaskCard: ChatSmallTaskMessageCardPayload? {
        guard case .smallTaskCard(let card) = payload else { return nil }
        return card
    }
    
    /// 深度思考卡片数据
    nonisolated var deepThoughtCard: ChatDeepThoughtCardPayload? {
        guard case .deepThought(let card) = payload else { return nil }
        return card
    }

    // MARK: - 构造器
    /// 便捷构造器：自动生成 ID、时间，传入类型与对应内容即可创建消息块
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
        self.toolCallId = toolCallID
        // 根据类型自动组装负载数据
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

    /// 解码构造器：从 JSON/数据中解析出消息块
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        let id = try c.decode(UUID.self, forKey: .key("id"))
        let anchor = try c.decodeIfPresent(ChatBlockAnchor.self, forKey: .key("anchor"))
        let kind = try c.decode(ChatMessageBlockKind.self, forKey: .key("kind"))
        let text = try c.decodeIfPresent(String.self, forKey: .key("text"))
        let toolName = try c.decodeIfPresent(String.self, forKey: .key("toolName"))
        let toolCallId = try c.decodeIfPresent(String.self, forKey: .key("toolCallId"))
        let attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .key("attachments")) ?? []
        let knowledgeCards = try c.decodeIfPresent([ChatKnowledgeCard].self, forKey: .key("knowledgeCards")) ?? []
        let taskCards = try c.decodeIfPresent([TaskCard].self, forKey: .key("taskCards")) ?? []
        let pendingMemberToolCards = try c.decodeIfPresent([PendingMemberToolCard].self, forKey: .key("pendingMemberToolCards")) ?? []
        let locations = try c.decodeIfPresent([ChatMapLocationPayload].self, forKey: .key("locations")) ?? []
        let routes = try c.decodeIfPresent([ChatRoutePayload].self, forKey: .key("routes")) ?? []
        let events = try c.decodeIfPresent([ChatEventPayload].self, forKey: .key("events")) ?? []
        let healthCards = try c.decodeIfPresent([ChatHealthCardPayload].self, forKey: .key("healthCards")) ?? []
        let structuredHealthCards = try c.decodeIfPresent(StructuredHealthCardsBlob.self, forKey: .key("structuredHealthCards"))
        let sleepVisualization = try c.decodeIfPresent(ChatHealthSleepModel.self, forKey: .key("sleepVisualization"))
        let workoutVisualization = try c.decodeIfPresent(ChatHealthWorkoutModel.self, forKey: .key("workoutVisualization"))
        let captureMessageCard = try c.decodeIfPresent(ChatCaptureMessageCardPayload.self, forKey: .key("captureMessageCard"))
        let smallTaskCard = try c.decodeIfPresent(ChatSmallTaskMessageCardPayload.self, forKey: .key("smallTaskCard"))
        let deepThoughtCard = try c.decodeIfPresent(ChatDeepThoughtCardPayload.self, forKey: .key("deepThoughtCard"))
        let createdAt = try c.decode(Date.self, forKey: .key("createdAt"))
        let updatedAt = try c.decode(Date.self, forKey: .key("updatedAt"))

        // 解析完成后调用便捷构造器赋值
        self.init(
            id: id,
            anchor: anchor,
            kind: kind,
            text: text,
            toolName: toolName,
            toolCallID: toolCallId,
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

    /// 编码方法：将消息块序列化为 JSON/数据
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(id, forKey: .key("id"))
        try c.encodeIfPresent(anchor, forKey: .key("anchor"))
        try c.encode(kind, forKey: .key("kind"))
        try c.encodeIfPresent(text, forKey: .key("text"))
        try c.encodeIfPresent(toolName, forKey: .key("toolName"))
        try c.encodeIfPresent(toolCallId, forKey: .key("toolCallId"))
        
        // 非空数据才编码，减少数据体积
        if attachments.isEmpty == false { try c.encode(attachments, forKey: .key("attachments")) }
        if knowledgeCards.isEmpty == false { try c.encode(knowledgeCards, forKey: .key("knowledgeCards")) }
        if taskCards.isEmpty == false { try c.encode(taskCards, forKey: .key("taskCards")) }
        if pendingMemberToolCards.isEmpty == false { try c.encode(pendingMemberToolCards, forKey: .key("pendingMemberToolCards")) }
        if locations.isEmpty == false { try c.encode(locations, forKey: .key("locations")) }
        if routes.isEmpty == false { try c.encode(routes, forKey: .key("routes")) }
        if events.isEmpty == false { try c.encode(events, forKey: .key("events")) }
        if healthCards.isEmpty == false { try c.encode(healthCards, forKey: .key("healthCards")) }
        
        try c.encodeIfPresent(structuredHealthCards, forKey: .key("structuredHealthCards"))
        try c.encodeIfPresent(sleepVisualization, forKey: .key("sleepVisualization"))
        try c.encodeIfPresent(workoutVisualization, forKey: .key("workoutVisualization"))
        try c.encodeIfPresent(captureMessageCard, forKey: .key("captureMessageCard"))
        try c.encodeIfPresent(smallTaskCard, forKey: .key("smallTaskCard"))
        try c.encodeIfPresent(deepThoughtCard, forKey: .key("deepThoughtCard"))
        
        try c.encode(createdAt, forKey: .key("createdAt"))
        try c.encode(updatedAt, forKey: .key("updatedAt"))
    }

    // MARK: - 私有工具方法
    /// 根据块类型，自动生成对应的负载数据（核心工厂方法）
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
            // 无传入时创建默认思考卡片
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
            // 必须传入可视化数据，否则触发开发时崩溃
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
        self.toolCallId = toolCallID
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
    let threadId: UUID
    let role: ChatMessageRole
    let blocks: [ChatMessageBlock]
    let clientMessageId: UUID
    let serverMessageId: String?
    let deliveryState: ChatDeliveryState
    let createdAt: Date
    let serverUpdatedAt: Date?
    let isTombstone: Bool
    let modelName: String?

    nonisolated var threadID: UUID { threadId }
    nonisolated var clientMessageID: UUID { clientMessageId }
    nonisolated var serverMessageID: String? { serverMessageId }

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
        self.threadId = threadID
        self.role = role
        self.blocks = blocks
        self.clientMessageId = clientMessageID
        self.serverMessageId = serverMessageID
        self.deliveryState = deliveryState
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.isTombstone = isTombstone
        self.modelName = modelName
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
