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

    func pull(cursor: String?) async throws -> ChatRemotePullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
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
