import Foundation

struct ChatRemoteMessageDTO: Codable, Sendable {
    let threadID: UUID
    let role: String
    let kind: String
    let content: String
    let clientMessageID: UUID
    let serverMessageID: String?
    let deliveryState: String
    let createdAt: Date
    let serverUpdatedAt: Date?
    let isTombstone: Bool
    let reasoningContent: String?
    let reasoningDurationMs: Int64?
    let reasoningExpanded: Bool?
    let reasoningVisibility: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case role
        case kind
        case content
        case clientMessageID = "client_message_id"
        case serverMessageID = "server_message_id"
        case deliveryState = "delivery_state"
        case createdAt = "created_at"
        case serverUpdatedAt = "server_updated_at"
        case isTombstone = "tombstone"
        case reasoningContent = "reasoning_content"
        case reasoningDurationMs = "reasoning_duration_ms"
        case reasoningExpanded = "reasoning_expanded"
        case reasoningVisibility = "reasoning_visibility"
    }

    init(
        threadID: UUID,
        role: String,
        kind: String,
        content: String,
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: String,
        createdAt: Date,
        serverUpdatedAt: Date?,
        isTombstone: Bool,
        reasoningContent: String? = nil,
        reasoningDurationMs: Int64? = nil,
        reasoningExpanded: Bool? = nil,
        reasoningVisibility: String? = nil
    ) {
        self.threadID = threadID
        self.role = role
        self.kind = kind
        self.content = content
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.deliveryState = deliveryState
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.isTombstone = isTombstone
        self.reasoningContent = reasoningContent
        self.reasoningDurationMs = reasoningDurationMs
        self.reasoningExpanded = reasoningExpanded
        self.reasoningVisibility = reasoningVisibility
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try c.decode(UUID.self, forKey: .threadID)
        role = try c.decode(String.self, forKey: .role)
        kind = try c.decode(String.self, forKey: .kind)
        content = try c.decode(String.self, forKey: .content)
        clientMessageID = try c.decode(UUID.self, forKey: .clientMessageID)
        serverMessageID = try c.decodeIfPresent(String.self, forKey: .serverMessageID)
        deliveryState = try c.decode(String.self, forKey: .deliveryState)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        serverUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
        isTombstone = try c.decodeIfPresent(Bool.self, forKey: .isTombstone) ?? false
        reasoningContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
        reasoningDurationMs = try c.decodeIfPresent(Int64.self, forKey: .reasoningDurationMs)
        reasoningExpanded = try c.decodeIfPresent(Bool.self, forKey: .reasoningExpanded)
        reasoningVisibility = try c.decodeIfPresent(String.self, forKey: .reasoningVisibility)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(role, forKey: .role)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encode(clientMessageID, forKey: .clientMessageID)
        try c.encodeIfPresent(serverMessageID, forKey: .serverMessageID)
        try c.encode(deliveryState, forKey: .deliveryState)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
        try c.encode(isTombstone, forKey: .isTombstone)
        try c.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        try c.encodeIfPresent(reasoningDurationMs, forKey: .reasoningDurationMs)
        try c.encodeIfPresent(reasoningExpanded, forKey: .reasoningExpanded)
        try c.encodeIfPresent(reasoningVisibility, forKey: .reasoningVisibility)
    }
}

struct ChatRemotePullResult: Sendable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
}

struct SparkChatRemoteAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 指定会话在服务端最新消息的 `server_updated_at`；无消息时为 `nil`。
    func threadHead(threadID: UUID) async throws -> Date? {
        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.ThreadHead",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/chat/sync/thread-head/",
                queryItems: [URLQueryItem(name: "thread_id", value: threadID.uuidString)],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.threadHead.\(threadID.uuidString)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatThreadHeadPayload.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return payload.lastServerUpdatedAt
    }

    func push(messages: [ChatRemoteMessageDTO]) async throws -> [ChatRemoteMessageDTO] {
        guard messages.isEmpty == false else { return [] }
        // 批量推送 outbox：服务端做幂等 upsert，客户端以回包为准更新本地状态。
        let requestBody = try ChatRemoteCoding.encoder.encode(ChatPushRequest(messages: messages))

        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.Push",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/chat/sync/push/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.push",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatPushResponse.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return payload.messages
    }

    /// - Parameters:
    ///   - cursor: 通常为本地已知的最新 `server_updated_at`（ISO8601）。
    ///   - threadID: 若指定，仅拉取该会话增量，避免进入单会话时拖回全账号历史。
    func pull(cursor: String?, threadID: UUID? = nil) async throws -> ChatRemotePullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let threadID {
            queryItems.append(URLQueryItem(name: "thread_id", value: threadID.uuidString))
        }
        // 增量拉取：cursor 由服务端 server_updated_at 驱动，避免全量扫描。

        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.Pull",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/chat/sync/pull/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.pull",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatPullResponse.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return ChatRemotePullResult(cursor: payload.cursor, messages: payload.messages)
    }
}

private struct ChatPushRequest: Encodable {
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatPushResponse: Decodable {
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatPullResponse: Decodable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatThreadHeadPayload: Decodable {
    let lastServerUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case lastServerUpdatedAt = "last_server_updated_at"
    }
}

private enum ChatRemoteCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 统一使用 ISO8601(含毫秒) 与 Django DateTimeField 对齐，减少时区歧义。
        encoder.dateEncodingStrategy = .custom { date, serializer in
            var container = serializer.singleValueContainer()
            try container.encode(ISO8601DateFormatter.chatFractional.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { serializer in
            let container = try serializer.singleValueContainer()
            if let text = try? container.decode(String.self) {
                if let parsed = ISO8601DateFormatter.chatFractional.date(from: text) {
                    return parsed
                }
                if let parsed = ISO8601DateFormatter.chatBasic.date(from: text) {
                    return parsed
                }
            }
            if let value = try? container.decode(Double.self) {
                let seconds = abs(value) > 100_000_000_000 ? value / 1000 : value
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = try? container.decode(Int.self) {
                let asDouble = Double(value)
                let seconds = abs(asDouble) > 100_000_000_000 ? asDouble / 1000 : asDouble
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported chat date value")
        }
        return decoder
    }()
}

private extension ISO8601DateFormatter {
    static let chatFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let chatBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
