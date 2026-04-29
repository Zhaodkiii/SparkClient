import Foundation

struct ChatRemoteMessageDTO: Codable, Sendable {
    let threadID: UUID
    let role: String
    let blocks: [ChatMessageBlock]
    let clientMessageID: UUID
    let serverMessageID: String?
    let deliveryState: String
    let createdAt: Date
    let serverUpdatedAt: Date?
    let isTombstone: Bool
    let threadCurrentModelName: String?
    let threadTemperature: Double?
    let threadTopP: Double?
    let threadMaxTokens: Int?
    let threadMaxMessages: Int?
    let threadRolePrompt: String?
    let threadSystemPrompt: String?
    let modelName: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case role
        case blocks
        case clientMessageID = "client_message_id"
        case serverMessageID = "server_message_id"
        case deliveryState = "delivery_state"
        case createdAt = "created_at"
        case serverUpdatedAt = "server_updated_at"
        case isTombstone = "tombstone"
        case threadCurrentModelName = "thread_current_model_name"
        case threadTemperature = "thread_temperature"
        case threadTopP = "thread_top_p"
        case threadMaxTokens = "thread_max_tokens"
        case threadMaxMessages = "thread_max_messages"
        case threadRolePrompt = "thread_role_prompt"
        case threadSystemPrompt = "thread_system_prompt"
        case modelName = "model_name"
    }

    nonisolated init(
        threadID: UUID,
        role: String,
        blocks: [ChatMessageBlock],
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: String,
        createdAt: Date,
        serverUpdatedAt: Date?,
        isTombstone: Bool,
        threadCurrentModelName: String? = nil,
        threadTemperature: Double? = nil,
        threadTopP: Double? = nil,
        threadMaxTokens: Int? = nil,
        threadMaxMessages: Int? = nil,
        threadRolePrompt: String? = nil,
        threadSystemPrompt: String? = nil,
        modelName: String? = nil
    ) {
        self.threadID = threadID
        self.role = role
        self.blocks = blocks
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.deliveryState = deliveryState
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.isTombstone = isTombstone
        self.threadCurrentModelName = threadCurrentModelName
        self.threadTemperature = threadTemperature
        self.threadTopP = threadTopP
        self.threadMaxTokens = threadMaxTokens
        self.threadMaxMessages = threadMaxMessages
        self.threadRolePrompt = threadRolePrompt
        self.threadSystemPrompt = threadSystemPrompt
        self.modelName = modelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try c.decode(UUID.self, forKey: .threadID)
        role = try c.decode(String.self, forKey: .role)
        blocks = try c.decode([ChatMessageBlock].self, forKey: .blocks)
        clientMessageID = try c.decode(UUID.self, forKey: .clientMessageID)
        serverMessageID = try c.decodeIfPresent(String.self, forKey: .serverMessageID)
        deliveryState = try c.decode(String.self, forKey: .deliveryState)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        serverUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
        isTombstone = try c.decodeIfPresent(Bool.self, forKey: .isTombstone) ?? false
        threadCurrentModelName = try c.decodeIfPresent(String.self, forKey: .threadCurrentModelName)
        threadTemperature = try c.decodeIfPresent(Double.self, forKey: .threadTemperature)
        threadTopP = try c.decodeIfPresent(Double.self, forKey: .threadTopP)
        threadMaxTokens = try c.decodeIfPresent(Int.self, forKey: .threadMaxTokens)
        threadMaxMessages = try c.decodeIfPresent(Int.self, forKey: .threadMaxMessages)
        let decodedThreadSystemPrompt = try c.decodeIfPresent(String.self, forKey: .threadSystemPrompt)
        let decodedThreadRolePrompt = try c.decodeIfPresent(String.self, forKey: .threadRolePrompt)
        threadSystemPrompt = decodedThreadSystemPrompt
        threadRolePrompt = decodedThreadSystemPrompt ?? decodedThreadRolePrompt
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(role, forKey: .role)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(clientMessageID, forKey: .clientMessageID)
        try c.encodeIfPresent(serverMessageID, forKey: .serverMessageID)
        try c.encode(deliveryState, forKey: .deliveryState)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
        try c.encode(isTombstone, forKey: .isTombstone)
        try c.encodeIfPresent(threadCurrentModelName, forKey: .threadCurrentModelName)
        try c.encodeIfPresent(threadTemperature, forKey: .threadTemperature)
        try c.encodeIfPresent(threadTopP, forKey: .threadTopP)
        try c.encodeIfPresent(threadMaxTokens, forKey: .threadMaxTokens)
        try c.encodeIfPresent(threadMaxMessages, forKey: .threadMaxMessages)
        try c.encodeIfPresent(threadRolePrompt, forKey: .threadRolePrompt)
        try c.encodeIfPresent(threadRolePrompt, forKey: .threadSystemPrompt)
        try c.encodeIfPresent(modelName, forKey: .modelName)
    }
}

struct ChatRemotePullResult: Sendable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
    let hasMore: Bool
}

struct ChatRemoteThreadDTO: Codable, Sendable {
    let threadID: UUID
    let title: String
    let scenario: String
    let patientID: UUID?
    let memberID: Int?
    let isDeleted: Bool
    let deletedAt: Date?
    let updatedAt: Date
    let serverUpdatedAt: Date
    let imageDeliveryModeRaw: String?
    let currentModelName: String?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let maxMessages: Int?
    let rolePrompt: String?
    let systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case title
        case scenario
        case patientID = "patient_id"
        case memberID = "member_id"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
        case serverUpdatedAt = "server_updated_at"
        case imageDeliveryModeRaw = "image_delivery_mode"
        case currentModelName = "current_model_name"
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case maxMessages = "max_messages"
        case rolePrompt = "role_prompt"
        case systemPrompt = "system_prompt"
    }

    nonisolated init(
        threadID: UUID,
        title: String,
        scenario: String,
        patientID: UUID?,
        memberID: Int?,
        isDeleted: Bool,
        deletedAt: Date?,
        updatedAt: Date,
        serverUpdatedAt: Date,
        imageDeliveryModeRaw: String?,
        currentModelName: String?,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        maxMessages: Int?,
        rolePrompt: String?,
        systemPrompt: String? = nil
    ) {
        self.threadID = threadID
        self.title = title
        self.scenario = scenario
        self.patientID = patientID
        self.memberID = memberID
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.imageDeliveryModeRaw = imageDeliveryModeRaw
        self.currentModelName = currentModelName
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.maxMessages = maxMessages
        self.rolePrompt = systemPrompt ?? rolePrompt
        self.systemPrompt = systemPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try c.decode(UUID.self, forKey: .threadID)
        title = try c.decode(String.self, forKey: .title)
        scenario = try c.decode(String.self, forKey: .scenario)
        patientID = try c.decodeIfPresent(UUID.self, forKey: .patientID)
        memberID = try c.decodeIfPresent(Int.self, forKey: .memberID)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        serverUpdatedAt = try c.decode(Date.self, forKey: .serverUpdatedAt)
        imageDeliveryModeRaw = try c.decodeIfPresent(String.self, forKey: .imageDeliveryModeRaw)
        currentModelName = try c.decodeIfPresent(String.self, forKey: .currentModelName)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try c.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        maxMessages = try c.decodeIfPresent(Int.self, forKey: .maxMessages)
        let decodedSystemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        let decodedRolePrompt = try c.decodeIfPresent(String.self, forKey: .rolePrompt)
        systemPrompt = decodedSystemPrompt
        rolePrompt = decodedSystemPrompt ?? decodedRolePrompt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(title, forKey: .title)
        try c.encode(scenario, forKey: .scenario)
        try c.encodeIfPresent(patientID, forKey: .patientID)
        try c.encodeIfPresent(memberID, forKey: .memberID)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(serverUpdatedAt, forKey: .serverUpdatedAt)
        try c.encodeIfPresent(imageDeliveryModeRaw, forKey: .imageDeliveryModeRaw)
        try c.encodeIfPresent(currentModelName, forKey: .currentModelName)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(topP, forKey: .topP)
        try c.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try c.encodeIfPresent(maxMessages, forKey: .maxMessages)
        try c.encodeIfPresent(rolePrompt, forKey: .rolePrompt)
        try c.encodeIfPresent(rolePrompt, forKey: .systemPrompt)
    }
}

struct ChatRemoteThreadPullResult: Sendable {
    let cursor: String?
    let threads: [ChatRemoteThreadDTO]
    let hasMore: Bool
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

    func pushThreads(_ threads: [ChatRemoteThreadDTO]) async throws -> [ChatRemoteThreadDTO] {
        guard threads.isEmpty == false else { return [] }
        let requestBody = try ChatRemoteCoding.encoder.encode(ChatThreadPushRequest(threads: threads))

        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.ThreadPush",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/chat/sync/thread-push/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.threadPush",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatThreadPushResponse.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return payload.threads
    }

    /// - Parameters:
    ///   - cursor: 通常为本地已知的最新 `server_updated_at`（ISO8601）。
    ///   - threadID: 若指定，仅拉取该会话增量，避免进入单会话时拖回全账号历史。
    func pull(cursor: String?, threadID: UUID? = nil, limit: Int? = nil) async throws -> ChatRemotePullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let threadID {
            queryItems.append(URLQueryItem(name: "thread_id", value: threadID.uuidString))
        }
        if let limit, limit > 0 {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
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
        return ChatRemotePullResult(
            cursor: payload.cursor,
            messages: payload.messages,
            hasMore: payload.hasMore ?? false
        )
    }

    /// 会话维度增量拉取：用于“会话列表本地优先 + 最少同步”。
    func pullThreads(cursor: String?, limit: Int = 100) async throws -> ChatRemoteThreadPullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(max(1, min(200, limit)))))

        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.ThreadPull",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/chat/sync/thread-pull/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.threadPull",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatThreadPullResponse.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return ChatRemoteThreadPullResult(
            cursor: payload.cursor,
            threads: payload.threads,
            hasMore: payload.hasMore ?? false
        )
    }

    /// 客户端软删会话后上送服务端。
    func deleteThreads(threadIDs: [UUID]) async throws -> [UUID] {
        guard threadIDs.isEmpty == false else { return [] }
        let requestBody = try ChatRemoteCoding.encoder.encode(ChatThreadDeleteRequest(threadIDs: threadIDs))
        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.ThreadDelete",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/chat/sync/thread-delete/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.threadDelete",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            ChatThreadDeleteResponse.self,
            from: response,
            decoder: ChatRemoteCoding.decoder
        )
        return payload.threadIDs
    }
}

private struct ChatPushRequest: Encodable {
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatThreadPushRequest: Encodable {
    let threads: [ChatRemoteThreadDTO]
}

private struct ChatThreadPushResponse: Decodable {
    let threads: [ChatRemoteThreadDTO]
}

private struct ChatPushResponse: Decodable {
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatPullResponse: Decodable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case cursor
        case messages
        case hasMore = "has_more"
    }
}

private struct ChatThreadPullResponse: Decodable {
    let cursor: String?
    let threads: [ChatRemoteThreadDTO]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case cursor
        case threads
        case hasMore = "has_more"
    }
}

private struct ChatThreadDeleteRequest: Encodable {
    let threadIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case threadIDs = "thread_ids"
    }
}

private struct ChatThreadDeleteResponse: Decodable {
    let threadIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case threadIDs = "thread_ids"
    }
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
