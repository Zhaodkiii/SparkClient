import Foundation

struct MemoryRemotePushResult: Sendable {
    let acks: [MemoryPushAckDTO]
}

struct MemoryRemotePullResult: Sendable {
    let cursor: String?
    let hasMore: Bool
    let items: [MemoryRemoteEntryDTO]
}

/// 记忆同步远端 API：对齐 `/api/v1/ai/memory/`，独立 serialKey，不与知识库/聊天共用。
struct SparkMemoryRemoteAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    func push(mutations: [MemoryMutationRequestDTO]) async throws -> MemoryRemotePushResult {
        guard mutations.isEmpty == false else {
            return MemoryRemotePushResult(acks: [])
        }
        let requestBody = try JSONEncoder.chatRemote.encode(MemoryPushRequest(mutations: mutations))
        let operation = CacheableSparkNetworkOperation(
            name: "Memory.Sync.Push",
            apiName: "MemoryRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/memory/sync/push/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "memory.sync.push",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            MemoryPushResponseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
        return MemoryRemotePushResult(acks: payload.results)
    }

    func pull(cursor: String?, limit: Int = 100) async throws -> MemoryRemotePullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(max(1, min(200, limit)))))
        let operation = CacheableSparkNetworkOperation(
            name: "Memory.Sync.Pull",
            apiName: "MemoryRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/memory/sync/pull/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "memory.sync.pull",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            MemoryPullResponseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
        return MemoryRemotePullResult(
            cursor: payload.nextCursor,
            hasMore: payload.hasMore ?? false,
            items: payload.items
        )
    }
}

private struct MemoryPushRequest: Encodable {
    let mutations: [MemoryMutationRequestDTO]
}
