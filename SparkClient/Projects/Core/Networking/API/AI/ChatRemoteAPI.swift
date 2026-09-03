import Foundation

struct ChatRemoteMessageDTO: Codable, Sendable {
    let threadId: UUID
    let role: String
    let blocks: [ChatMessageBlock]
    let clientMessageId: UUID
    let serverMessageId: String?
    let deliveryState: String
    let createdAt: Date
    let serverUpdatedAt: Date?
    let tombstone: Bool
    let threadCurrentModelName: String?
    let threadTemperature: Double?
    let threadTopP: Double?
    let threadMaxTokens: Int?
    let threadMaxMessages: Int?
    let threadRolePrompt: String?
    let threadSystemPrompt: String?
    let modelName: String?
    /// CHAT-000056：医院会话权威发送者快照。旧消息 / 非医院消息为 nil，不得据此推断为真人医生。
    /// 不要给这个属性默认值：Swift 合成 Decodable 可能因此跳过 JSON 里的 `sender`。
    let sender: ChatRemoteMessageSenderDTO?
}

nonisolated struct ChatRemoteMessageSenderDTO: Codable, Sendable {
    let actorType: String
    let actorId: String?
    let displayName: String?
    let avatarUrl: String?
    let title: String?
    let departmentName: String?
    let source: String?
}

struct ChatRemoteMessageBlockUpdateDTO: Codable, Sendable {
    let threadId: UUID
    let clientMessageId: UUID
    let block: ChatMessageBlock
}

struct ChatPushAcceptedMessageDTO: Codable, Sendable {
    let clientMessageId: UUID
    let serverMessageId: String?
    let serverUpdatedAt: Date
}

struct ChatPushAcceptedBlockUpdateDTO: Codable, Sendable {
    let clientMessageId: UUID
    let blockId: UUID
    let serverUpdatedAt: Date
}

struct ChatPushAckResponse: Codable, Sendable {
    let acceptedMessages: [ChatPushAcceptedMessageDTO]
    let acceptedBlockUpdates: [ChatPushAcceptedBlockUpdateDTO]
}

struct ChatRemotePullResult: Sendable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
    let hasMore: Bool
}

struct ChatRemoteThreadDTO: Codable, Sendable {
    let threadId: UUID
    let title: String
    let scenario: String
    let patientId: UUID?
    let memberId: Int?
    let isDeleted: Bool
    let deletedAt: Date?
    let updatedAt: Date
    let serverUpdatedAt: Date
    let imageDeliveryMode: String?
    let iconName: String?
    let iconColorName: String?
    let isPinned: Bool?
    let pinnedAt: Date?
    let currentModelName: String?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let maxMessages: Int?
    let rolePrompt: String?
    let systemPrompt: String?

    nonisolated var threadID: UUID { threadId }
    nonisolated var patientID: UUID? { patientId }
    nonisolated var memberID: Int? { memberId }
    nonisolated var imageDeliveryModeRaw: String? { imageDeliveryMode }

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
        iconName: String? = nil,
        iconColorName: String? = nil,
        isPinned: Bool? = nil,
        pinnedAt: Date? = nil,
        currentModelName: String?,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        maxMessages: Int?,
        rolePrompt: String?,
        systemPrompt: String? = nil
    ) {
        self.threadId = threadID
        self.title = title
        self.scenario = scenario
        self.patientId = patientID
        self.memberId = memberID
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.imageDeliveryMode = imageDeliveryModeRaw
        self.iconName = iconName
        self.iconColorName = iconColorName
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.currentModelName = currentModelName
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.maxMessages = maxMessages
        self.rolePrompt = systemPrompt ?? rolePrompt
        self.systemPrompt = systemPrompt
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
            decoder: JSONDecoder.chatRemote
        )
        return payload.lastServerUpdatedAt
    }

    func push(messages: [ChatRemoteMessageDTO]) async throws -> ChatPushAckResponse {
        guard messages.isEmpty == false else {
            return ChatPushAckResponse(acceptedMessages: [], acceptedBlockUpdates: [])
        }
        // 批量推送 outbox：服务端持久化后以 ACK 元数据回包，客户端不 merge 完整 messages。
        let requestBody = try JSONEncoder.chatRemote.encode(ChatPushRequest(messages: messages))

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
        return try APIResponseDecoder.decodeWrappedData(
            ChatPushAckResponse.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
    }

    func pushBlockUpdates(_ updates: [ChatRemoteMessageBlockUpdateDTO]) async throws -> ChatPushAckResponse {
        guard updates.isEmpty == false else {
            return ChatPushAckResponse(acceptedMessages: [], acceptedBlockUpdates: [])
        }
        let requestBody = try JSONEncoder.chatRemote.encode(ChatBlockPushRequest(blockUpdates: updates))

        let operation = CacheableSparkNetworkOperation(
            name: "Chat.Sync.PushBlocks",
            apiName: "ChatRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/chat/sync/push/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.sync.push.blocks",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(
            ChatPushAckResponse.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
    }

    func pushThreads(_ threads: [ChatRemoteThreadDTO]) async throws -> [ChatRemoteThreadDTO] {
        guard threads.isEmpty == false else { return [] }
        let requestBody = try JSONEncoder.chatRemote.encode(ChatThreadPushRequest(threads: threads))

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
            decoder: JSONDecoder.chatRemote
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
            decoder: JSONDecoder.chatRemote
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
            decoder: JSONDecoder.chatRemote
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
        let requestBody = try JSONEncoder.chatRemote.encode(ChatThreadDeleteRequest(threadIDs: threadIDs))
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
            decoder: JSONDecoder.chatRemote
        )
        return payload.threadIDs
    }
}

private struct ChatPushRequest: Encodable {
    let messages: [ChatRemoteMessageDTO]
}

private struct ChatBlockPushRequest: Encodable {
    let blockUpdates: [ChatRemoteMessageBlockUpdateDTO]
}

private struct ChatThreadPushRequest: Encodable {
    let threads: [ChatRemoteThreadDTO]
}

private struct ChatThreadPushResponse: Decodable {
    let threads: [ChatRemoteThreadDTO]
}

private struct ChatPullResponse: Decodable {
    let cursor: String?
    let messages: [ChatRemoteMessageDTO]
    let hasMore: Bool?

}

private struct ChatThreadPullResponse: Decodable {
    let cursor: String?
    let threads: [ChatRemoteThreadDTO]
    let hasMore: Bool?

}

private struct ChatThreadDeleteRequest: Encodable {
    let threadIds: [UUID]

    init(threadIDs: [UUID]) {
        self.threadIds = threadIDs
    }
}

private struct ChatThreadDeleteResponse: Decodable {
    let threadIds: [UUID]

    nonisolated var threadIDs: [UUID] { threadIds }
}

private struct ChatThreadHeadPayload: Decodable {
    let lastServerUpdatedAt: Date?

}

