import Foundation

nonisolated enum DeepTutorMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

nonisolated struct DeepTutorMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let conversationID: UUID
    let role: DeepTutorMessageRole
    let content: String
    let capability: DeepTutorCapability
    let events: [DeepTutorStreamEvent]
    let attachments: [DeepTutorAttachment]
    let requestSnapshot: DeepTutorRequestSnapshot?
    let parentMessageID: UUID?
    let blocks: [DeepTutorMessageBlock]
    let serverID: String?
    let status: DeepTutorMessageStatus
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool

    nonisolated var clientMessageID: UUID { id }

    nonisolated init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: DeepTutorMessageRole,
        content: String,
        capability: DeepTutorCapability = .chat,
        events: [DeepTutorStreamEvent] = [],
        attachments: [DeepTutorAttachment] = [],
        requestSnapshot: DeepTutorRequestSnapshot? = nil,
        parentMessageID: UUID? = nil,
        blocks: [DeepTutorMessageBlock] = [],
        serverID: String? = nil,
        status: DeepTutorMessageStatus = .ready,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.capability = capability
        self.events = events
        self.attachments = attachments
        self.requestSnapshot = requestSnapshot
        self.parentMessageID = parentMessageID
        self.blocks = blocks
        self.serverID = serverID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    func replacing(
        content: String? = nil,
        events: [DeepTutorStreamEvent]? = nil,
        attachments: [DeepTutorAttachment]? = nil,
        blocks: [DeepTutorMessageBlock]? = nil,
        status: DeepTutorMessageStatus? = nil,
        updatedAt: Date = Date()
    ) -> DeepTutorMessage {
        DeepTutorMessage(
            id: id,
            conversationID: conversationID,
            role: role,
            content: content ?? self.content,
            capability: capability,
            events: events ?? self.events,
            attachments: attachments ?? self.attachments,
            requestSnapshot: requestSnapshot,
            parentMessageID: parentMessageID,
            blocks: blocks ?? self.blocks,
            serverID: serverID,
            status: status ?? self.status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}

nonisolated struct DeepTutorConversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var currentModelName: String?
    var temperature: Double?
    var topP: Double
    var maxMessages: Int
    var rolePrompt: String?
    var memberID: Int?

    nonisolated var generationSettings: DeepTutorConversationGenerationSettings {
        DeepTutorConversationGenerationSettings(
            currentModelName: currentModelName,
            temperature: temperature,
            topP: topP,
            maxMessages: maxMessages
        )
    }

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        currentModelName: String? = nil,
        temperature: Double? = nil,
        topP: Double = 1.0,
        maxMessages: Int = 20,
        rolePrompt: String? = nil,
        memberID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.currentModelName = currentModelName
        self.temperature = temperature
        self.topP = topP
        self.maxMessages = maxMessages
        self.rolePrompt = rolePrompt
        self.memberID = memberID
    }
}

nonisolated struct DeepTutorConversationListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let conversation: DeepTutorConversation
    let latestPreview: String
    let latestMessageAt: Date
    let latestMessageStatus: DeepTutorMessageStatus?

    init(
        id: UUID,
        conversation: DeepTutorConversation,
        latestPreview: String,
        latestMessageAt: Date,
        latestMessageStatus: DeepTutorMessageStatus? = nil
    ) {
        self.id = id
        self.conversation = conversation
        self.latestPreview = latestPreview
        self.latestMessageAt = latestMessageAt
        self.latestMessageStatus = latestMessageStatus
    }
}
