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
    /// 工具用户问答消息内卡片块
    case toolQuestionCards
    /// 工具成员选择消息内卡片块
    case toolMemberSelectionCards
    /// 健康资料候选选择消息内卡片块
    case healthResourceCandidateCards
    /// 工具结果发送给 AI 前的数据授权消息内卡片块
    case toolConsentCards
    /// 结构化健康卡片块
    case structuredHealthCards
    /// 睡眠可视化展示块
    case sleepVisualization
    /// 营养卡片块（写入 Apple 健康）
    case nutritionCards
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
    /// 助手回复状态卡片（中断、失败等）
    case assistantStatusCard
    /// 健康资料引用（问报告）
    case healthResourceReference
    /// 医疗风险提示
    case medicalRiskNotice
    /// 医疗分析免责声明（客户端自动追加，非工具）
    case medicalDisclaimerCard
}

nonisolated enum ChatMessageBlockStatus: String, Codable, Sendable {
    case pending
    case streaming
    case ready
    case failed
}

nonisolated enum ChatMessageBlockNodeRole: String, Codable, Sendable {
    case timeline
    case tool
    case toolPresentation
}

nonisolated enum ChatStableBlockID {
    static func textSegment(messageID: UUID, index: Int) -> UUID {
        deterministicUUID("chat.message.\(messageID.uuidString.lowercased()).block.text.\(index)")
    }

    static func reasoning(messageID: UUID) -> UUID {
        deterministicUUID("chat.message.\(messageID.uuidString.lowercased()).block.reasoning")
    }

    static func tool(messageID: UUID, toolCallID: String) -> UUID {
        deterministicUUID("chat.message.\(messageID.uuidString.lowercased()).tool.\(toolCallID).row")
    }

    static func rich(messageID: UUID, toolCallID: String, kind: ChatMessageBlockKind) -> UUID {
        deterministicUUID("chat.message.\(messageID.uuidString.lowercased()).tool.\(toolCallID).rich.\(kind.rawValue)")
    }

    static func rich(messageID: UUID, kind: ChatMessageBlockKind) -> UUID {
        deterministicUUID("chat.message.\(messageID.uuidString.lowercased()).rich.\(kind.rawValue)")
    }

    static func healthResource(
        messageID: UUID,
        resourceType: String,
        resourceID: Int,
        memberID: Int
    ) -> UUID {
        deterministicUUID(
            "chat.message.\(messageID.uuidString.lowercased()).health.\(resourceType).\(resourceID).\(memberID)"
        )
    }

    private static func deterministicUUID(_ key: String) -> UUID {
        var hash1: UInt64 = 0xcbf29ce484222325
        var hash2: UInt64 = 0x84222325cbf29ce4
        for byte in key.utf8 {
            hash1 ^= UInt64(byte)
            hash1 &*= 0x100000001b3
            hash2 ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            hash2 &*= 0x100000001b3
        }
        var byteArray = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: hash1.bigEndian) { raw in
            for index in 0..<8 { byteArray[index] = raw[index] }
        }
        withUnsafeBytes(of: hash2.bigEndian) { raw in
            for index in 0..<8 { byteArray[index + 8] = raw[index] }
        }
        byteArray[6] = (byteArray[6] & 0x0f) | 0x50
        byteArray[8] = (byteArray[8] & 0x3f) | 0x80
        let bytes: uuid_t = (
            byteArray[0], byteArray[1], byteArray[2], byteArray[3],
            byteArray[4], byteArray[5], byteArray[6], byteArray[7],
            byteArray[8], byteArray[9], byteArray[10], byteArray[11],
            byteArray[12], byteArray[13], byteArray[14], byteArray[15]
        )
        return UUID(uuid: bytes)
    }
}

nonisolated enum ChatMessageBlockPayload: Codable, Equatable, Sendable {
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
    case toolQuestionCards([ChatToolQuestionCard])
    case toolMemberSelectionCards([ChatToolMemberSelectionCard])
    case healthResourceCandidateCards([ChatHealthResourceCandidateSelectionCard])
    case toolConsentCards([ChatToolConsentCard])
    case structuredHealthCards(StructuredHealthCardsBlob)
    case sleepVisualization(ChatHealthSleepModel)
    case nutritionCards(ChatNutritionCardsPayload)
    case workoutVisualization(ChatHealthWorkoutModel)
    case captureCard(ChatCaptureMessageCardPayload)
    case html(String)
    case smallTaskCard(ChatSmallTaskMessageCardPayload)
    case taskCards([TaskCard])
    case error(String)
    case assistantStatusCard(ChatAssistantStatusCardPayload)
    case healthResourceReference(ChatHealthResourceReferencePayload)
    case medicalRiskNotice(ChatMedicalRiskNoticePayload)
    case medicalDisclaimerCard(ChatMedicalDisclaimerCardPayload)

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
        case .toolQuestionCards: return .toolQuestionCards
        case .toolMemberSelectionCards: return .toolMemberSelectionCards
        case .healthResourceCandidateCards: return .healthResourceCandidateCards
        case .toolConsentCards: return .toolConsentCards
        case .structuredHealthCards: return .structuredHealthCards
        case .sleepVisualization: return .sleepVisualization
        case .nutritionCards: return .nutritionCards
        case .workoutVisualization: return .workoutVisualization
        case .captureCard: return .captureCard
        case .html: return .html
        case .smallTaskCard: return .smallTaskCard
        case .taskCards: return .taskCards
        case .error: return .error
        case .assistantStatusCard: return .assistantStatusCard
        case .healthResourceReference: return .healthResourceReference
        case .medicalRiskNotice: return .medicalRiskNotice
        case .medicalDisclaimerCard: return .medicalDisclaimerCard
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
    let parentToolCallId: String?
    let parentBlockId: UUID?
    let nodeRole: ChatMessageBlockNodeRole
    /// 消息块负载数据（核心内容）
    let payload: ChatMessageBlockPayload
    /// Streaming lifecycle for this block. Rich cards should move pending -> ready/failed on the same stable id.
    let status: ChatMessageBlockStatus
    /// Monotonic local revision used by idempotent DB upserts.
    let revision: Int64
    /// Stable presentation ordering that does not depend on array merge timing.
    let orderKey: Double?
    /// 创建时间
    let createdAt: Date
    /// 更新时间
    let updatedAt: Date

    // MARK: - 计算属性（快捷访问 payload 内容）
    /// 工具调用 ID（兼容命名）
    nonisolated var toolCallID: String? { toolCallId }
    nonisolated var parentToolCallID: String? { parentToolCallId }
    nonisolated var parentBlockID: UUID? { parentBlockId }
    
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
        case .assistantStatusCard(let card):
            return card.message
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

    /// 工具执行归一化参数：仅工具类型块有效
    nonisolated var toolInvocationArguments: [String: String]? {
        guard case .tool(let tool) = payload else { return nil }
        return tool.invocationArguments
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

    /// 工具用户问答消息内卡片列表
    nonisolated var toolQuestionCards: [ChatToolQuestionCard] {
        guard case .toolQuestionCards(let cards) = payload else { return [] }
        return cards
    }

    /// 工具成员选择消息内卡片列表
    nonisolated var toolMemberSelectionCards: [ChatToolMemberSelectionCard] {
        guard case .toolMemberSelectionCards(let cards) = payload else { return [] }
        return cards
    }

    /// 健康资料候选选择消息内卡片列表
    nonisolated var healthResourceCandidateCards: [ChatHealthResourceCandidateSelectionCard] {
        guard case .healthResourceCandidateCards(let cards) = payload else { return [] }
        return cards
    }

    /// 工具结果发送给 AI 前的数据授权消息内卡片列表
    nonisolated var toolConsentCards: [ChatToolConsentCard] {
        guard case .toolConsentCards(let cards) = payload else { return [] }
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

    /// 营养卡片数据
    nonisolated var nutritionCards: ChatNutritionCardsPayload? {
        guard case .nutritionCards(let payload) = payload else { return nil }
        return payload
    }

    /// 医疗风险提示
    nonisolated var medicalRiskNotice: ChatMedicalRiskNoticePayload? {
        guard case .medicalRiskNotice(let payload) = payload else { return nil }
        return payload
    }

    /// 医疗分析免责声明
    nonisolated var medicalDisclaimerCard: ChatMedicalDisclaimerCardPayload? {
        guard case .medicalDisclaimerCard(let payload) = payload else { return nil }
        return payload
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
        toolInvocationArguments: [String: String]? = nil,
        toolCallID: String? = nil,
        parentToolCallID: String? = nil,
        parentBlockID: UUID? = nil,
        nodeRole: ChatMessageBlockNodeRole? = nil,
        attachments: [ChatAttachment] = [],
        knowledgeCards: [ChatKnowledgeCard] = [],
        taskCards: [TaskCard] = [],
        pendingMemberToolCards: [PendingMemberToolCard] = [],
        toolQuestionCards: [ChatToolQuestionCard] = [],
        toolMemberSelectionCards: [ChatToolMemberSelectionCard] = [],
        healthResourceCandidateCards: [ChatHealthResourceCandidateSelectionCard] = [],
        toolConsentCards: [ChatToolConsentCard] = [],
        locations: [ChatMapLocationPayload] = [],
        routes: [ChatRoutePayload] = [],
        events: [ChatEventPayload] = [],
        healthCards: [ChatHealthCardPayload] = [],
        structuredHealthCards: StructuredHealthCardsBlob? = nil,
        sleepVisualization: ChatHealthSleepModel? = nil,
        nutritionCards: ChatNutritionCardsPayload? = nil,
        workoutVisualization: ChatHealthWorkoutModel? = nil,
        captureMessageCard: ChatCaptureMessageCardPayload? = nil,
        smallTaskCard: ChatSmallTaskMessageCardPayload? = nil,
        deepThoughtCard: ChatDeepThoughtCardPayload? = nil,
        assistantStatusCard: ChatAssistantStatusCardPayload? = nil,
        healthResourceReference: ChatHealthResourceReferencePayload? = nil,
        medicalRiskNotice: ChatMedicalRiskNoticePayload? = nil,
        medicalDisclaimerCard: ChatMedicalDisclaimerCardPayload? = nil,
        status: ChatMessageBlockStatus = .ready,
        revision: Int64 = 1,
        orderKey: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.anchor = anchor
        self.toolCallId = toolCallID
        self.parentToolCallId = parentToolCallID
        self.parentBlockId = parentBlockID
        self.nodeRole = nodeRole ?? Self.defaultNodeRole(kind: kind, toolCallID: toolCallID, parentToolCallID: parentToolCallID)
        // 根据类型自动组装负载数据
        self.payload = Self.makePayload(
            kind: kind,
            text: text,
            toolName: toolName,
            toolInvocationArguments: toolInvocationArguments,
            attachments: attachments,
            knowledgeCards: knowledgeCards,
            taskCards: taskCards,
            pendingMemberToolCards: pendingMemberToolCards,
            toolQuestionCards: toolQuestionCards,
            toolMemberSelectionCards: toolMemberSelectionCards,
            healthResourceCandidateCards: healthResourceCandidateCards,
            toolConsentCards: toolConsentCards,
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
            assistantStatusCard: assistantStatusCard,
            healthResourceReference: healthResourceReference,
            medicalRiskNotice: medicalRiskNotice,
            medicalDisclaimerCard: medicalDisclaimerCard
        )
        self.status = status
        self.revision = revision
        self.orderKey = orderKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - 私有工具方法
    /// 根据块类型，自动生成对应的负载数据（核心工厂方法）
    private nonisolated static func makePayload(
        kind: ChatMessageBlockKind,
        text: String?,
        toolName: String?,
        toolInvocationArguments: [String: String]?,
        attachments: [ChatAttachment],
        knowledgeCards: [ChatKnowledgeCard],
        taskCards: [TaskCard],
        pendingMemberToolCards: [PendingMemberToolCard],
        toolQuestionCards: [ChatToolQuestionCard],
        toolMemberSelectionCards: [ChatToolMemberSelectionCard],
        healthResourceCandidateCards: [ChatHealthResourceCandidateSelectionCard],
        toolConsentCards: [ChatToolConsentCard],
        locations: [ChatMapLocationPayload],
        routes: [ChatRoutePayload],
        events: [ChatEventPayload],
        healthCards: [ChatHealthCardPayload],
        structuredHealthCards: StructuredHealthCardsBlob?,
        sleepVisualization: ChatHealthSleepModel?,
        nutritionCards: ChatNutritionCardsPayload?,
        workoutVisualization: ChatHealthWorkoutModel?,
        captureMessageCard: ChatCaptureMessageCardPayload?,
        smallTaskCard: ChatSmallTaskMessageCardPayload?,
        deepThoughtCard: ChatDeepThoughtCardPayload?,
        assistantStatusCard: ChatAssistantStatusCardPayload?,
        healthResourceReference: ChatHealthResourceReferencePayload?,
        medicalRiskNotice: ChatMedicalRiskNoticePayload?,
        medicalDisclaimerCard: ChatMedicalDisclaimerCardPayload?
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
            return .tool(.init(
                name: toolName,
                content: text ?? "",
                invocationArguments: toolInvocationArguments
            ))
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
        case .toolQuestionCards:
            return .toolQuestionCards(toolQuestionCards)
        case .toolMemberSelectionCards:
            return .toolMemberSelectionCards(toolMemberSelectionCards)
        case .healthResourceCandidateCards:
            return .healthResourceCandidateCards(healthResourceCandidateCards)
        case .toolConsentCards:
            return .toolConsentCards(toolConsentCards)
        case .structuredHealthCards:
            return .structuredHealthCards(structuredHealthCards ?? .empty)
        case .sleepVisualization:
            // 必须传入可视化数据，否则触发开发时崩溃
            guard let sleepVisualization else {
                preconditionFailure("Missing sleep visualization payload for sleepVisualization block")
            }
            return .sleepVisualization(sleepVisualization)
        case .nutritionCards:
            guard let nutritionCards else {
                preconditionFailure("Missing nutrition cards payload for nutritionCards block")
            }
            return .nutritionCards(nutritionCards)
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
        case .assistantStatusCard:
            guard let assistantStatusCard else {
                preconditionFailure("Missing assistant status card payload")
            }
            return .assistantStatusCard(assistantStatusCard)
        case .healthResourceReference:
            guard let healthResourceReference else {
                preconditionFailure("Missing health resource reference payload")
            }
            return .healthResourceReference(healthResourceReference)
        case .medicalRiskNotice:
            guard let medicalRiskNotice else {
                preconditionFailure("Missing medical risk notice payload for medicalRiskNotice block")
            }
            return .medicalRiskNotice(medicalRiskNotice)
        case .medicalDisclaimerCard:
            guard let medicalDisclaimerCard else {
                preconditionFailure("Missing medical disclaimer payload for medicalDisclaimerCard block")
            }
            return .medicalDisclaimerCard(medicalDisclaimerCard)
        }
    }

    private nonisolated static func defaultNodeRole(
        kind: ChatMessageBlockKind,
        toolCallID: String?,
        parentToolCallID: String?
    ) -> ChatMessageBlockNodeRole {
        if kind == .medicalDisclaimerCard { return .timeline }
        if kind == .tool { return .tool }
        if parentToolCallID?.isEmpty == false { return .toolPresentation }
        if toolCallID?.isEmpty == false, kind != .text, kind != .deepThought, kind != .error, kind != .assistantStatusCard {
            return .toolPresentation
        }
        return .timeline
    }
}

extension ChatMessageBlock {
    /// Payload-backed round-trip used by chat block storage and sync payloads.
    fileprivate nonisolated init(
        id: UUID,
        anchor: ChatBlockAnchor?,
        toolCallID: String?,
        parentToolCallID: String? = nil,
        parentBlockID: UUID? = nil,
        nodeRole: ChatMessageBlockNodeRole? = nil,
        payload: ChatMessageBlockPayload,
        status: ChatMessageBlockStatus = .ready,
        revision: Int64 = 1,
        orderKey: Double? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.anchor = anchor
        self.toolCallId = toolCallID
        self.parentToolCallId = parentToolCallID
        self.parentBlockId = parentBlockID
        self.nodeRole = nodeRole ?? Self.defaultNodeRole(kind: payload.kind, toolCallID: toolCallID, parentToolCallID: parentToolCallID)
        self.payload = payload
        self.status = status
        self.revision = revision
        self.orderKey = orderKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated func replacingPayload(
        _ payload: ChatMessageBlockPayload,
        status: ChatMessageBlockStatus,
        revision: Int64? = nil,
        updatedAt: Date = Date()
    ) -> ChatMessageBlock {
        ChatMessageBlock(
            id: id,
            anchor: anchor,
            toolCallID: toolCallID,
            parentToolCallID: parentToolCallID,
            parentBlockID: parentBlockID,
            nodeRole: nodeRole,
            payload: payload,
            status: status,
            revision: revision ?? self.revision + 1,
            orderKey: orderKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func replacingIdentity(
        id: UUID,
        orderKey: Double? = nil
    ) -> ChatMessageBlock {
        ChatMessageBlock(
            id: id,
            anchor: anchor,
            toolCallID: toolCallID,
            parentToolCallID: parentToolCallID,
            parentBlockID: parentBlockID,
            nodeRole: nodeRole,
            payload: payload,
            status: status,
            revision: revision,
            orderKey: orderKey ?? self.orderKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

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
    let usageSummary: ChatMessageUsageSummary?

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
        modelName: String? = nil,
        usageSummary: ChatMessageUsageSummary? = nil
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
        self.usageSummary = usageSummary
    }

}

extension ChatMessage {
    nonisolated func replacingBlocks(_ blocks: [ChatMessageBlock]) -> ChatMessage {
        ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            blocks: blocks,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: serverUpdatedAt,
            isTombstone: isTombstone,
            modelName: modelName,
            usageSummary: usageSummary
        )
    }

    /// 会话内阻塞式工具交互卡片属于本地优先的展示块。流式输出和远端回包可能暂时不包含这些块，
    /// 刷新 UI 快照时需要保留，避免卡片一闪而过。
    nonisolated func mergingLocalInlineToolInteractionBlocks(from local: ChatMessage) -> ChatMessage {
        guard clientMessageID == local.clientMessageID else { return self }
        let currentIDs = Set(blocks.map(\.id))
        let preservedLocal = local.blocks.filter { block in
            block.isInlineToolInteractionPresentationBlock && currentIDs.contains(block.id) == false
        }
        guard preservedLocal.isEmpty == false else { return self }
        var mergedBlocks = blocks + preservedLocal
        mergedBlocks.sort { lhs, rhs in
            switch (lhs.orderKey, rhs.orderKey) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.createdAt < rhs.createdAt
            }
        }
        return ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            blocks: mergedBlocks,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: serverUpdatedAt,
            isTombstone: isTombstone,
            modelName: modelName,
            usageSummary: usageSummary
        )
    }

    /// 入站合并时保留本地已落库的 `healthResourceReference`（远端 push/拉取可能尚未支持该 block）。
    nonisolated func mergingRemotePreservingLocalHealthResourceBlocks(_ remote: ChatMessage) -> ChatMessage {
        guard clientMessageID == remote.clientMessageID else { return remote }
        let remoteHealthIDs = Set(
            remote.blocks
                .filter { $0.kind == .healthResourceReference }
                .map(\.id)
        )
        let preservedLocal = blocks.filter { block in
            block.kind == .healthResourceReference && remoteHealthIDs.contains(block.id) == false
        }
        guard preservedLocal.isEmpty == false else { return remote }
        var mergedBlocks = remote.blocks + preservedLocal
        mergedBlocks.sort { lhs, rhs in
            switch (lhs.orderKey, rhs.orderKey) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.createdAt < rhs.createdAt
            }
        }
        return ChatMessage(
            id: remote.id,
            threadID: remote.threadID,
            role: remote.role,
            blocks: mergedBlocks,
            clientMessageID: remote.clientMessageID,
            serverMessageID: remote.serverMessageID ?? serverMessageID,
            deliveryState: remote.deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.isTombstone,
            modelName: remote.modelName,
            usageSummary: remote.usageSummary ?? usageSummary
        )
    }

    /// 由工具消息块构造全局工具详情 Sheet 的载荷（含同 `toolCallID` 关联块 id）。
    nonisolated func makeToolPreviewPrompt(forToolBlock toolBlock: ChatMessageBlock) -> ToolPreviewPrompt? {
        guard case .tool(let t) = toolBlock.payload else { return nil }
        let nextToolOrderKey = blocks
            .filter { $0.nodeRole == .tool && $0.id != toolBlock.id }
            .compactMap(\.orderKey)
            .filter { next in
                guard let current = toolBlock.orderKey else { return false }
                return next > current
            }
            .min()
        let related = blocks.filter {
            guard $0.id != toolBlock.id, $0.nodeRole == .toolPresentation else { return false }
            if ($0.parentToolCallID ?? $0.toolCallID) == toolBlock.toolCallID {
                return true
            }
            guard $0.isInlineToolInteractionPresentationBlock,
                  let toolOrder = toolBlock.orderKey,
                  let blockOrder = $0.orderKey,
                  blockOrder > toolOrder
            else {
                return false
            }
            if let nextToolOrderKey {
                return blockOrder < nextToolOrderKey
            }
            return true
        }
        return ToolPreviewPrompt(
            toolName: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: t.name),
            toolContent: t.content,
            toolArguments: t.invocationArguments,
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

extension ChatMessageBlock {
    nonisolated var isInlineToolInteractionPresentationBlock: Bool {
        guard nodeRole == .toolPresentation else { return false }
        return kind == .toolQuestionCards
            || kind == .toolMemberSelectionCards
            || kind == .healthResourceCandidateCards
            || kind == .toolConsentCards
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
