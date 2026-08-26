import Foundation

struct KnowledgeRemotePushResult: Sendable {
    let acks: [KnowledgePushAckDTO]
}

struct KnowledgeRemotePullResult: Sendable {
    let cursor: String?
    let hasMore: Bool
    let documents: [KnowledgeRemoteDocumentDTO]
}

/// 知识库同步远端 API：对齐 `/api/v1/ai/knowledge/` 契约，写法与 `SparkChatRemoteAPI` 一致
/// （`isIdempotent: true` + 独立 `serialKey`），但使用独立的 cursor/Outbox，不与 Chat 共用。
struct SparkKnowledgeRemoteAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 幂等获取或创建当前账号的默认个人知识库。
    func fetchDefaultBase() async throws -> KnowledgeDefaultBaseDTO {
        let operation = CacheableSparkNetworkOperation(
            name: "Knowledge.Sync.DefaultBase",
            apiName: "KnowledgeRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/knowledge/default/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "knowledge.sync.defaultBase",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(
            KnowledgeDefaultBaseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
    }

    /// 批量幂等 Push；单条冲突不阻断同批其它 mutation，逐条 ACK 由调用方处理。
    func push(mutations: [KnowledgeMutationRequestDTO]) async throws -> KnowledgeRemotePushResult {
        guard mutations.isEmpty == false else {
            return KnowledgeRemotePushResult(acks: [])
        }
        let requestBody = try JSONEncoder.chatRemote.encode(KnowledgePushRequest(mutations: mutations))

        let operation = CacheableSparkNetworkOperation(
            name: "Knowledge.Sync.Push",
            apiName: "KnowledgeRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/knowledge/sync/push/",
                body: .raw(requestBody, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "knowledge.sync.push",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            KnowledgePushResponseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
        return KnowledgeRemotePushResult(acks: payload.results)
    }

    /// 增量 Pull：`cursor` 为服务端 opaque token，客户端不解析其内容。
    func pull(cursor: String?, limit: Int = 100) async throws -> KnowledgeRemotePullResult {
        var queryItems: [URLQueryItem] = []
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(max(1, min(200, limit)))))

        let operation = CacheableSparkNetworkOperation(
            name: "Knowledge.Sync.Pull",
            apiName: "KnowledgeRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/knowledge/sync/pull/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "knowledge.sync.pull",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(
            KnowledgePullResponseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
        return KnowledgeRemotePullResult(
            cursor: payload.cursor,
            hasMore: payload.hasMore ?? false,
            documents: payload.documents
        )
    }
}

private struct KnowledgePushRequest: Encodable {
    let mutations: [KnowledgeMutationRequestDTO]
}
