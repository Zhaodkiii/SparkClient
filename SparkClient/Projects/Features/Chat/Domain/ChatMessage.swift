import Foundation

enum ChatMessageRole: String, Codable, Sendable {
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

enum ChatMessageKind: String, Codable, Sendable {
    case text
    case tool
    case card
    case system
}

enum ChatBlockAnchor: Codable, Equatable, Sendable {
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

enum ChatMessageBlockKind: String, Codable, Sendable {
    case text
    case reasoning
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
    case captureCard
    case html
    case smallTaskCard
    case taskCards
    case error
}

struct ChatToolBlockPayload: Codable, Equatable, Sendable {
    let name: String?
    let content: String
}

struct ChatMapRouteBlockPayload: Codable, Equatable, Sendable {
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
}

enum ChatMessageBlockPayload: Equatable, Sendable {
    case text(String)
    case reasoning(String)
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
    case captureCard(ChatCaptureMessageCardPayload)
    case html(String)
    case smallTaskCard(ChatSmallTaskMessageCardPayload)
    case taskCards([TaskCard])
    case error(String)

    var kind: ChatMessageBlockKind {
        switch self {
        case .text: return .text
        case .reasoning: return .reasoning
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
        case .captureCard: return .captureCard
        case .html: return .html
        case .smallTaskCard: return .smallTaskCard
        case .taskCards: return .taskCards
        case .error: return .error
        }
    }
}

struct ChatMessageBlock: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let anchor: ChatBlockAnchor?
    let toolCallID: String?
    let payload: ChatMessageBlockPayload
    let createdAt: Date
    let updatedAt: Date

    var kind: ChatMessageBlockKind { payload.kind }
    var text: String? {
        switch payload {
        case .text(let text),
                .reasoning(let text),
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
    var toolName: String? {
        guard case .tool(let tool) = payload else { return nil }
        return tool.name
    }
    var attachments: [ChatAttachment] {
        switch payload {
        case .imageGallery(let attachments), .fileAttachments(let attachments):
            return attachments
        default:
            return []
        }
    }
    var knowledgeCards: [ChatKnowledgeCard] {
        guard case .knowledgeCards(let cards) = payload else { return [] }
        return cards
    }
    var taskCards: [TaskCard] {
        guard case .taskCards(let cards) = payload else { return [] }
        return cards
    }
    var pendingMemberToolCards: [PendingMemberToolCard] {
        guard case .pendingMemberToolCards(let cards) = payload else { return [] }
        return cards
    }
    var locations: [ChatMapLocationPayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.locations
    }
    var routes: [ChatRoutePayload] {
        guard case .mapRoute(let route) = payload else { return [] }
        return route.routes
    }
    var events: [ChatEventPayload] {
        guard case .events(let events) = payload else { return [] }
        return events
    }
    var healthCards: [ChatHealthCardPayload] {
        guard case .healthCards(let cards) = payload else { return [] }
        return cards
    }
    var structuredHealthCards: StructuredHealthCardsBlob? {
        guard case .structuredHealthCards(let blob) = payload else { return nil }
        return blob
    }
    var sleepVisualization: ChatHealthSleepModel? {
        guard case .sleepVisualization(let model) = payload else { return nil }
        return model
    }
    var captureMessageCard: ChatCaptureMessageCardPayload? {
        guard case .captureCard(let card) = payload else { return nil }
        return card
    }
    var smallTaskCard: ChatSmallTaskMessageCardPayload? {
        guard case .smallTaskCard(let card) = payload else { return nil }
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
        captureMessageCard: ChatCaptureMessageCardPayload? = nil,
        smallTaskCard: ChatSmallTaskMessageCardPayload? = nil,
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
            captureMessageCard: captureMessageCard,
            smallTaskCard: smallTaskCard
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
        case captureMessageCard
        case smallTaskCard
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
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
        let captureMessageCard = try c.decodeIfPresent(ChatCaptureMessageCardPayload.self, forKey: .captureMessageCard)
        let smallTaskCard = try c.decodeIfPresent(ChatSmallTaskMessageCardPayload.self, forKey: .smallTaskCard)
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
            captureMessageCard: captureMessageCard,
            smallTaskCard: smallTaskCard,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
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
        try c.encodeIfPresent(captureMessageCard, forKey: .captureMessageCard)
        try c.encodeIfPresent(smallTaskCard, forKey: .smallTaskCard)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private static func makePayload(
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
        captureMessageCard: ChatCaptureMessageCardPayload?,
        smallTaskCard: ChatSmallTaskMessageCardPayload?
    ) -> ChatMessageBlockPayload {
        switch kind {
        case .text:
            return .text(text ?? "")
        case .reasoning:
            return .reasoning(text ?? "")
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

struct ChatMessageStorageEnvelope: Codable, Equatable, Sendable {
    let attachments: [ChatAttachment]
    let blocks: [ChatMessageBlock]
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let threadID: UUID
    let role: ChatMessageRole
    let kind: ChatMessageKind
    let content: String
    let attachments: [ChatAttachment]
    let blocks: [ChatMessageBlock]
    var reasoningContent: String?
    var reasoningDurationMs: Int64?
    var reasoningExpanded: Bool
    var reasoningVisibility: ChatReasoningVisibility
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
        kind: ChatMessageKind = .text,
        content: String,
        attachments: [ChatAttachment] = [],
        blocks: [ChatMessageBlock]? = nil,
        reasoningContent: String? = nil,
        reasoningDurationMs: Int64? = nil,
        reasoningExpanded: Bool = false,
        reasoningVisibility: ChatReasoningVisibility = .full,
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
        self.kind = kind
        self.content = content
        self.attachments = attachments
        self.reasoningContent = reasoningContent
        self.reasoningDurationMs = reasoningDurationMs
        self.reasoningExpanded = reasoningExpanded
        self.reasoningVisibility = reasoningVisibility
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.deliveryState = deliveryState
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.isTombstone = isTombstone
        self.modelName = modelName
        self.blocks = blocks ?? ChatMessageBlockBuilder.legacyBlocks(
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            createdAt: createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case role
        case kind
        case content
        case attachments
        case blocks
        case reasoningContent
        case reasoningDurationMs
        case reasoningExpanded
        case reasoningVisibility
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
        kind = try c.decodeIfPresent(ChatMessageKind.self, forKey: .kind) ?? .text
        content = try c.decode(String.self, forKey: .content)
        attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        reasoningContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
        reasoningDurationMs = try c.decodeIfPresent(Int64.self, forKey: .reasoningDurationMs)
        reasoningExpanded = try c.decodeIfPresent(Bool.self, forKey: .reasoningExpanded) ?? false
        reasoningVisibility = try c.decodeIfPresent(ChatReasoningVisibility.self, forKey: .reasoningVisibility) ?? .full
        clientMessageID = try c.decode(UUID.self, forKey: .clientMessageID)
        serverMessageID = try c.decodeIfPresent(String.self, forKey: .serverMessageID)
        deliveryState = try c.decode(ChatDeliveryState.self, forKey: .deliveryState)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        serverUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
        isTombstone = try c.decodeIfPresent(Bool.self, forKey: .isTombstone) ?? false
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
        blocks = try c.decodeIfPresent([ChatMessageBlock].self, forKey: .blocks)
            ?? ChatMessageBlockBuilder.legacyBlocks(
                role: role,
                kind: kind,
                content: content,
                attachments: attachments,
                reasoningContent: reasoningContent,
                reasoningDurationMs: reasoningDurationMs,
                createdAt: createdAt
            )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(role, forKey: .role)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(blocks, forKey: .blocks)
        try c.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        try c.encodeIfPresent(reasoningDurationMs, forKey: .reasoningDurationMs)
        try c.encode(reasoningExpanded, forKey: .reasoningExpanded)
        try c.encode(reasoningVisibility, forKey: .reasoningVisibility)
        try c.encode(clientMessageID, forKey: .clientMessageID)
        try c.encodeIfPresent(serverMessageID, forKey: .serverMessageID)
        try c.encode(deliveryState, forKey: .deliveryState)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
        try c.encode(isTombstone, forKey: .isTombstone)
        try c.encodeIfPresent(modelName, forKey: .modelName)
    }
}

enum ChatMessageBlockBuilder {
    nonisolated static func blocks(from attachments: [ChatAttachment], createdAt: Date) -> [ChatMessageBlock] {
        anchored(blocks: [], attachments: attachments, createdAt: createdAt)
    }

    nonisolated static func attachments(from blocks: [ChatMessageBlock]) -> [ChatAttachment] {
        var out: [ChatAttachment] = []
        for block in blocks {
            switch block.kind {
            case .pendingMemberToolCards:
                guard block.pendingMemberToolCards.isEmpty == false else { continue }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                guard let data = try? encoder.encode(block.pendingMemberToolCards),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(
                    ChatAttachment(
                        type: .pendingMemberToolCards,
                        text: text,
                        anchorToolCallID: block.toolCallID ?? block.pendingMemberToolCards.first?.toolCallID,
                        anchorBlockID: block.anchor?.blockID
                    )
                )
            case .taskCards:
                guard block.taskCards.isEmpty == false,
                      let data = try? JSONEncoder().encode(block.taskCards),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .taskCards, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .knowledgeCards:
                guard block.knowledgeCards.isEmpty == false,
                      let data = try? JSONEncoder().encode(block.knowledgeCards),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .knowledgeCard, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .structuredHealthCards:
                guard let blob = block.structuredHealthCards,
                      let data = try? JSONEncoder().encode(blob),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .structuredHealthCards, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .sleepVisualization:
                guard let model = block.sleepVisualization,
                      let data = try? JSONEncoder().encode(model),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .healthSleepVisualization, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .captureCard:
                guard let payload = block.captureMessageCard,
                      let data = try? JSONEncoder().encode(payload),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .captureMessageCard, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .html:
                if let text = block.text, text.isEmpty == false {
                    out.append(ChatAttachment(type: .htmlContent, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
                }
            case .mapRoute:
                if block.locations.isEmpty == false,
                   let data = try? JSONEncoder().encode(block.locations),
                   let text = String(data: data, encoding: .utf8) {
                    out.append(ChatAttachment(type: .locationsInfo, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
                }
                if block.routes.isEmpty == false,
                   let data = try? JSONEncoder().encode(block.routes),
                   let text = String(data: data, encoding: .utf8) {
                    out.append(ChatAttachment(type: .routeInfo, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
                }
            case .events:
                guard block.events.isEmpty == false,
                      let data = try? JSONEncoder().encode(block.events),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .events, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .healthCards:
                guard block.healthCards.isEmpty == false,
                      let data = try? JSONEncoder().encode(block.healthCards),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .healthInfo, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .translatedText:
                if let text = block.text, text.isEmpty == false {
                    out.append(ChatAttachment(type: .translatedText, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
                }
            case .smallTaskCard:
                guard let payload = block.smallTaskCard,
                      let data = try? JSONEncoder().encode(payload),
                      let text = String(data: data, encoding: .utf8) else { continue }
                out.append(ChatAttachment(type: .smallTaskCard, text: text, anchorToolCallID: block.toolCallID, anchorBlockID: block.anchor?.blockID))
            case .imageGallery, .fileAttachments:
                out.append(contentsOf: block.attachments)
            case .text, .reasoning, .tool, .error:
                continue
            }
        }
        return out
    }

    nonisolated static func mergeRichBlocks(
        existingBlocks: [ChatMessageBlock],
        incomingBlocks: [ChatMessageBlock]
    ) -> [ChatMessageBlock] {
        var result = existingBlocks
        for block in incomingBlocks {
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

    /// 流式 `normalizeStreamingBlocks` 之后补一次锚点归位，使 `taskCards` / `pendingMemberToolCards` 等与睡眠卡一致贴在对应 `toolCall` 后。
    nonisolated static func finalizeStreamingPresentationBlocks(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        stabilizeToolAnchoredPresentationBlockOrder(blocks)
    }

    nonisolated static func legacyBlocks(
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        createdAt: Date
    ) -> [ChatMessageBlock] {
        let metadata = LegacyMetadata(attachments: attachments)
        var blocks: [ChatMessageBlock] = []

        if role == .assistant,
           let reasoning = reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           reasoning.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .reasoning, text: reasoning, createdAt: createdAt, updatedAt: createdAt))
        }

        let imageAttachments = attachments.filter(\.isChatImageLike)
        if imageAttachments.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .imageGallery, attachments: imageAttachments, createdAt: createdAt, updatedAt: createdAt))
        }

        if role == .assistant,
           let toolContent = metadata.toolContent,
           toolContent.isEmpty == false {
            blocks.append(
                ChatMessageBlock(
                    kind: .tool,
                    text: toolContent,
                    toolName: metadata.toolName,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
        }

        if metadata.knowledgeCards.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .knowledgeCards, knowledgeCards: metadata.knowledgeCards, createdAt: createdAt, updatedAt: createdAt))
        }
        if let translated = metadata.translatedText, translated.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .translatedText, text: translated, createdAt: createdAt, updatedAt: createdAt))
        }
        if metadata.locations.isEmpty == false || metadata.routes.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .mapRoute, locations: metadata.locations, routes: metadata.routes, createdAt: createdAt, updatedAt: createdAt))
        }
        if metadata.events.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .events, events: metadata.events, createdAt: createdAt, updatedAt: createdAt))
        }
        if metadata.healthCards.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .healthCards, healthCards: metadata.healthCards, createdAt: createdAt, updatedAt: createdAt))
        }
        if metadata.pendingMemberToolCards.isEmpty == false {
            blocks.append(contentsOf: metadata.pendingMemberToolCards.map {
                ChatMessageBlock(
                    anchor: .toolCall($0.toolCallID ?? ""),
                    kind: .pendingMemberToolCards,
                    pendingMemberToolCards: [$0],
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            })
        }
        if let blob = metadata.structuredHealthCards,
           blob.medications.isEmpty == false
            || blob.prescriptions.isEmpty == false
            || blob.examReports.isEmpty == false
            || blob.medicalCases.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .structuredHealthCards, structuredHealthCards: blob, createdAt: createdAt, updatedAt: createdAt))
        }
//        if let sleep = metadata.sleepVisualization {
//            blocks.append(ChatMessageBlock(kind: .sleepVisualization, sleepVisualization: sleep, createdAt: createdAt, updatedAt: createdAt))
//        }
        if let capture = metadata.captureMessageCard {
            blocks.append(ChatMessageBlock(kind: .captureCard, captureMessageCard: capture, createdAt: createdAt, updatedAt: createdAt))
        }
        if let html = metadata.htmlContent, html.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .html, text: html, createdAt: createdAt, updatedAt: createdAt))
        }
        if role == .user, let smallTask = metadata.smallTaskCard {
            blocks.append(ChatMessageBlock(kind: .smallTaskCard, smallTaskCard: smallTask, createdAt: createdAt, updatedAt: createdAt))
        }

        let fileAttachments = attachments.filter(\.isGenericFileAttachment)
        if fileAttachments.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .fileAttachments, attachments: fileAttachments, createdAt: createdAt, updatedAt: createdAt))
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .text, text: content, createdAt: createdAt, updatedAt: createdAt))
        }

        if metadata.taskCards.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .taskCards, taskCards: metadata.taskCards, createdAt: createdAt, updatedAt: createdAt))
        }

        if blocks.isEmpty {
            blocks.append(ChatMessageBlock(kind: .text, text: content, createdAt: createdAt, updatedAt: createdAt))
        }
        return anchored(blocks: blocks, attachments: attachments, createdAt: createdAt)
    }

    nonisolated static func merge(
        existingBlocks: [ChatMessageBlock],
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        createdAt: Date
    ) -> [ChatMessageBlock] {
        let legacy = legacyBlocks(
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            createdAt: createdAt
        )
        guard existingBlocks.isEmpty == false else { return legacy }
        let structuralKinds: Set<ChatMessageBlockKind> = [.text, .reasoning, .tool, .error]
        var merged = existingBlocks.filter { structuralKinds.contains($0.kind) }
        let toolIDs = Set(merged.compactMap(\.toolCallID))
        for block in legacy {
            if structuralKinds.contains(block.kind) == false {
                merged.append(block)
            } else if block.kind == .tool,
                      let toolCallID = block.toolCallID,
                      toolIDs.contains(toolCallID) == false {
                merged.append(block)
            }
        }
        return stabilizeToolAnchoredPresentationBlockOrder(
            anchored(blocks: merged, attachments: attachments, createdAt: createdAt)
        )
    }

    nonisolated private static func anchored(
        blocks: [ChatMessageBlock],
        attachments: [ChatAttachment],
        createdAt: Date
    ) -> [ChatMessageBlock] {
        var result = blocks
        let anchoredAttachments = attachments.filter {
            ($0.anchorToolCallID?.isEmpty == false) || $0.anchorBlockID != nil
        }
        guard anchoredAttachments.isEmpty == false else { return result }
        for attachment in anchoredAttachments {
            guard let block = block(from: attachment, createdAt: createdAt) else { continue }
            if let blockID = attachment.anchorBlockID,
               let index = result.firstIndex(where: { $0.id == blockID }) {
                result.insert(block, at: index + 1)
                continue
            }
            if let toolCallID = attachment.anchorToolCallID,
               let index = result.lastIndex(where: { $0.toolCallID == toolCallID }) {
                result.insert(block, at: index + 1)
                continue
            }
            result.append(block)
        }
        return deduplicated(result)
    }

    /// 【非孤立静态方法】查找要替换的消息块索引
    /// 在现有 blocks 数组中，找到**应该被新块替换**的旧块位置
    /// - Parameters:
    ///   - blocks: 现有的消息块数组
    ///   - incoming: 新进来的、要替换旧块的消息块
    /// - Returns: 找到的索引，找不到返回 nil
    nonisolated private static func replacementIndex(
        in blocks: [ChatMessageBlock],
        for incoming: ChatMessageBlock
    ) -> Int? {

        // 情况1：新块是【待处理成员工具卡片】
        // 按卡片ID查找，找到就替换
        if let firstCard = incoming.pendingMemberToolCards.first {
            return blocks.firstIndex { block in
                block.kind == .pendingMemberToolCards
                    && block.pendingMemberToolCards.contains(where: { $0.id == firstCard.id })
            }
        }
        
        

        // 情况2：新块是结构化健康卡、睡眠可视化、拍照卡片、HTML预览
        // 按【块类型 + 工具调用ID + 锚点】三者匹配查找
        if incoming.kind == .structuredHealthCards
            || incoming.kind == .sleepVisualization
            || incoming.kind == .captureCard
            || incoming.kind == .html {
            return blocks.firstIndex {
                $0.kind == incoming.kind
                && $0.toolCallID == incoming.toolCallID
                && $0.anchor == incoming.anchor
            }
        }

        // 情况3：新块带有【工具调用ID】
        // 按【块类型 + toolCallID + 锚点】匹配
        if let toolCallID = incoming.toolCallID {
            return blocks.firstIndex {
                $0.kind == incoming.kind
                && $0.toolCallID == toolCallID
                && $0.anchor == incoming.anchor
            }
        }

        // 都不满足 → 没有可替换的旧块
        return nil
    }
    
    
    nonisolated private static func anchoredInsertIndex(
        in blocks: [ChatMessageBlock],
        for incoming: ChatMessageBlock
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

    nonisolated private static func mergedReplacement(
        original: ChatMessageBlock,
        incoming: ChatMessageBlock
    ) -> ChatMessageBlock {
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
            captureMessageCard: incoming.captureMessageCard,
            smallTaskCard: incoming.smallTaskCard,
            createdAt: original.createdAt,
            updatedAt: incoming.updatedAt
        )
    }

    nonisolated private static func deduplicated(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        var seenAttachmentIDs: Set<UUID> = []
        var seenPendingCardIDs: Set<UUID> = []
        var out: [ChatMessageBlock] = []
        for block in blocks {
            switch block.kind {
            case .pendingMemberToolCards:
                let ids = block.pendingMemberToolCards.map(\.id)
                guard ids.allSatisfy({ seenPendingCardIDs.insert($0).inserted }) else { continue }
            case .captureCard, .structuredHealthCards, .sleepVisualization, .html:
                if out.contains(where: { $0.kind == block.kind && $0 == block }) {
                    continue
                }
            default:
                break
            }
            if block.attachments.isEmpty == false {
                let inserted = block.attachments.allSatisfy { seenAttachmentIDs.insert($0.id).inserted }
                if inserted == false { continue }
            }
            out.append(block)
        }
        return out
    }

    /// 将带 `toolCall` 锚点、且非「工具行」本身的内容块，紧挨在对应 `toolCallID` 的 **最后一条工具行** 之后。
    /// 流式/异步合并时可能出现「卡片已合入、工具行稍后才出现」，块会暂存在数组尾部；落库与 `merge(…)` 走同一条归一化即可稳定顺序。
    nonisolated private static func stabilizeToolAnchoredPresentationBlockOrder(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        guard blocks.count > 1 else { return blocks }
        var reordered = blocks
        for _ in 0..<32 {
            var didChange = false
            let blockIDsToRelocate: [UUID] = reordered.compactMap { block in
                guard block.kind != .tool, case .toolCall = block.anchor else { return nil }
                return block.id
            }
            for blockID in blockIDsToRelocate {
                guard let currentIndex = reordered.firstIndex(where: { $0.id == blockID }) else { continue }
                let block = reordered[currentIndex]
                guard case .toolCall(let toolCallID) = block.anchor, toolCallID.isEmpty == false else { continue }
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
            if didChange == false { break }
        }
        return reordered
    }

    nonisolated private static func block(from attachment: ChatAttachment, createdAt: Date) -> ChatMessageBlock? {
        guard let raw = attachment.text?.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        switch attachment.type {
        case .pendingMemberToolCards:
            guard let cards = try? decoder.decode([PendingMemberToolCard].self, from: raw), cards.isEmpty == false else { return nil }
            return ChatMessageBlock(
                anchor: attachment.anchorToolCallID.map(ChatBlockAnchor.toolCall),
                kind: .pendingMemberToolCards,
                pendingMemberToolCards: cards,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        case .structuredHealthCards:
            guard let blob = try? decoder.decode(StructuredHealthCardsBlob.self, from: raw) else { return nil }
            return ChatMessageBlock(
                anchor: attachment.anchorToolCallID.map(ChatBlockAnchor.toolCall),
                kind: .structuredHealthCards,
                structuredHealthCards: blob,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        case .taskCards:
            guard let cards = try? decoder.decode([TaskCard].self, from: raw), cards.isEmpty == false else { return nil }
            return ChatMessageBlock(
                anchor: attachment.anchorToolCallID.map(ChatBlockAnchor.toolCall),
                kind: .taskCards,
                toolCallID: attachment.anchorToolCallID,
                taskCards: cards,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        case .knowledgeCard:
            guard let cards = try? decoder.decode([ChatKnowledgeCard].self, from: raw), cards.isEmpty == false else { return nil }
            return ChatMessageBlock(
                anchor: attachment.anchorToolCallID.map(ChatBlockAnchor.toolCall),
                kind: .knowledgeCards,
                toolCallID: attachment.anchorToolCallID,
                knowledgeCards: cards,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        case .healthSleepVisualization:
            guard let model = try? decoder.decode(ChatHealthSleepModel.self, from: raw) else { return nil }
            return ChatMessageBlock(
                anchor: attachment.anchorToolCallID.map(ChatBlockAnchor.toolCall),
                kind: .sleepVisualization,
                toolCallID: attachment.anchorToolCallID,
                sleepVisualization: model,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        default:
            return nil
        }
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

private struct LegacyMetadata {
    let toolName: String?
    let toolContent: String?
    let knowledgeCards: [ChatKnowledgeCard]
    let translatedText: String?
    let htmlContent: String?
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
    let events: [ChatEventPayload]
    let healthCards: [ChatHealthCardPayload]
    let sleepVisualization: ChatHealthSleepModel?
    let taskCards: [TaskCard]
    let pendingMemberToolCards: [PendingMemberToolCard]
    let structuredHealthCards: StructuredHealthCardsBlob?
    let captureMessageCard: ChatCaptureMessageCardPayload?
    let smallTaskCard: ChatSmallTaskMessageCardPayload?

    init(attachments: [ChatAttachment]) {
        func text(_ type: ChatAttachmentType) -> String? {
            let value = attachments.first(where: { $0.type == type })?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, value.isEmpty == false else { return nil }
            return value
        }
        func decodeArray<T: Decodable>(_ type: ChatAttachmentType) -> [T] {
            guard let raw = text(type), let data = raw.data(using: .utf8) else { return [] }
            if let rows = try? JSONDecoder().decode([T].self, from: data) { return rows }
            if let row = try? JSONDecoder().decode(T.self, from: data) { return [row] }
            return []
        }
        func decodeObject<T: Decodable>(_ type: ChatAttachmentType) -> T? {
            guard let raw = text(type), let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        toolName = text(.toolName)
        toolContent = text(.toolContent)
        knowledgeCards = decodeArray(.knowledgeCard)
        translatedText = text(.translatedText)
        htmlContent = text(.htmlContent)
        locations = decodeArray(.locationsInfo)
        routes = decodeArray(.routeInfo)
        events = decodeArray(.events)
        healthCards = decodeArray(.healthInfo)
        sleepVisualization = decodeObject(.healthSleepVisualization)
        taskCards = decodeArray(.taskCards)
        pendingMemberToolCards = decodeArray(.pendingMemberToolCards)
        structuredHealthCards = decodeObject(.structuredHealthCards)
        captureMessageCard = decodeObject(.captureMessageCard)
        smallTaskCard = decodeObject(.smallTaskCard)
    }
}

extension ChatMessage {
    nonisolated static func shouldPreferRemoteUserImageSyncData(local: ChatMessage, remote: ChatMessage) -> Bool {
        guard local.clientMessageID == remote.clientMessageID else { return false }
        guard local.role == .user, remote.role == .user else { return false }
        let localScore = userImageRichAttachmentScore(local)
        let remoteScore = userImageRichAttachmentScore(remote)
        return remoteScore > localScore
    }

    nonisolated private static func userImageRichAttachmentScore(_ message: ChatMessage) -> Int {
        var score = 0
        for att in message.attachments where att.isChatImageLike {
            if att.effectiveHTTPSImageDownloadURL != nil {
                score += 8
                continue
            }
            var piece = 0
            if let k = att.fullCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), k.isEmpty == false { piece += 2 }
            if let md5 = att.fileMd5?.trimmingCharacters(in: .whitespacesAndNewlines), md5.isEmpty == false { piece += 2 }
            if let fid = att.fileId, fid > 0 { piece += 2 }
            if let t = att.text?.trimmingCharacters(in: .whitespacesAndNewlines), t.isEmpty == false { piece += 1 }
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
