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
    /// 模型名称（最终消费时按名称匹配模型信息与头像）。
    let modelName: String?

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
        try c.encodeIfPresent(modelName, forKey: .modelName)
    }
}

// MARK: - 同步合并（用户图片附件）

extension ChatMessage {
    /// 同一 `clientMessageID` 的用户消息：若远端附件携带的可下载/可缓存信息明显多于本地，则必须采纳远端。
    ///
    /// 背景：`CoreDataChatStore.upsertRemoteMessages` 曾仅用 `serverUpdatedAt` 决定是否跳过写入；本地若因
    /// `updateMessageDeliveryState` 等把 `serverUpdatedAt` 刷得比服务端新，但附件行仍是旧/空数据，会永久挡住
    /// pull 下来的完整 `url` / `fullCacheKey` / `fileMd5`，进而出现「同步里有图、下载时 attachment 全空」。
    nonisolated static func shouldPreferRemoteUserImageSyncData(local: ChatMessage, remote: ChatMessage) -> Bool {
        guard local.clientMessageID == remote.clientMessageID else { return false }
        guard local.role == .user, remote.role == .user else { return false }
        let localScore = userImageRichAttachmentScore(local)
        let remoteScore = userImageRichAttachmentScore(remote)
        return remoteScore > localScore
    }

    /// 对「类聊天图片」附件打分：有 https 地址权重最高；否则累计缓存键、MD5、file_id、OCR 文本等。
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
    /// 最新消息中首张可同步下载的图片（用于列表缩略图）。
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
