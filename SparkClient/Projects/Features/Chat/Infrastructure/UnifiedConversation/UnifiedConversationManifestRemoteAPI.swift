import Foundation

/// CHAT-000057 29.3/30.3：统一消息会话 Manifest 远端 API。
///
/// 服务端未上线时 404 → 抛出 `.endpointUnavailable`，由同步层按「保留缓存、不误降级」处理。
struct UnifiedConversationManifestRemoteAPI: Sendable {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 拉取一页 Manifest 变更（cursor 为空表示首次全量快照）。
    func fetchManifestPage(cursor: String?, limit: Int = 200) async throws -> UnifiedConversationManifestPageDTO {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let operation = CacheableSparkNetworkOperation(
            name: "Chat.UnifiedConversationManifest",
            apiName: "UnifiedConversationManifestRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/chat/conversations/manifest/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "chat.conversations.manifest",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        do {
            let response = try await configuration.execute(operation)
            return try APIResponseDecoder.decodeWrappedData(
                UnifiedConversationManifestPageDTO.self,
                from: response,
                decoder: JSONDecoder.chatRemote
            )
        } catch SparkNetworkError.httpError(let statusCode, _, _) {
            switch statusCode {
            case 404:
                throw UnifiedConversationManifestSyncError.endpointUnavailable
            case 410:
                throw UnifiedConversationManifestSyncError.cursorExpired
            case 409:
                throw UnifiedConversationManifestSyncError.resetRequired
            default:
                throw UnifiedConversationManifestSyncError.httpFailure(statusCode)
            }
        }
    }
}

/// CHAT-000057 30.3：Manifest 同步错误语义。
enum UnifiedConversationManifestSyncError: Error, Equatable {
    /// 服务端未部署 Manifest：保留现有缓存与本地兼容分类，不重试刷屏
    case endpointUnavailable
    /// cursor 失效：触发受控全量重建
    case cursorExpired
    /// 服务端要求丢弃旧绑定缓存并重建
    case resetRequired
    /// schema 不兼容：停止应用变更
    case schemaUnsupported(Int)
    /// 其他 HTTP 失败：保留缓存与旧 cursor，退避重试
    case httpFailure(Int)
    /// 解析/校验失败：保留缓存，不推进 cursor
    case validationFailed(String)
}

/// 供 UseCase 依赖注入与单元测试 mock 使用的只读接口面。
protocol UnifiedConversationManifestRemoteServing: Sendable {
    func fetchManifestPage(cursor: String?, limit: Int) async throws -> UnifiedConversationManifestPageDTO
}

extension UnifiedConversationManifestRemoteAPI: UnifiedConversationManifestRemoteServing {}
