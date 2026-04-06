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

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let threadID: UUID
    let role: ChatMessageRole
    let kind: ChatMessageKind
    let content: String
    let attachments: [ChatAttachment]
    /// Assistant reasoning / chain-of-thought text (separate from final answer).
    var reasoningContent: String?
    /// Wall-clock duration of reasoning phase in milliseconds (optional).
    var reasoningDurationMs: Int64?
    var reasoningExpanded: Bool
    var reasoningVisibility: ChatReasoningVisibility
    let clientMessageID: UUID
    let serverMessageID: String?
    let deliveryState: ChatDeliveryState
    let createdAt: Date
    let serverUpdatedAt: Date?
    let isTombstone: Bool

    nonisolated init(
        id: UUID = UUID(),
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind = .text,
        content: String,
        attachments: [ChatAttachment] = [],
        reasoningContent: String? = nil,
        reasoningDurationMs: Int64? = nil,
        reasoningExpanded: Bool = false,
        reasoningVisibility: ChatReasoningVisibility = .full,
        clientMessageID: UUID = UUID(),
        serverMessageID: String? = nil,
        deliveryState: ChatDeliveryState = .pending,
        createdAt: Date = Date(),
        serverUpdatedAt: Date? = nil,
        isTombstone: Bool = false
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
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case role
        case kind
        case content
        case attachments
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(role, forKey: .role)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encode(attachments, forKey: .attachments)
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
