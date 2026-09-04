import Foundation

/// CHAT-000056：结构化实时同步提示。
/// 网络层只负责解析实时同步提示，不直接访问 Core Data 或 ViewModel。
nonisolated struct ChatSyncHint: Sendable {
    /// 单次通知关联 ID，仅用于诊断与日志关联，不作为消息 ID。
    let eventID: UUID?
    /// 事件载荷版本：1 = 旧版（无 thread_id），2 = 本期契约。
    let payloadVersion: Int
    /// 本次变化所属会话；v1 或无法解析时为 nil——调用方必须走账号级全局补偿，不得猜测当前会话。
    let threadID: UUID?
    /// 服务端“已有更新”的提示游标；不直接覆盖本地已提交的同步 cursor。
    let cursor: String?
    /// 受影响的服务端消息 ID，可用于诊断与拉取完成校验。
    let messageIDs: [String]
    /// 服务端事件发送时间，用于链路耗时诊断。
    let emittedAt: Date?
}

actor ChatRealtimeSyncClient {
    typealias SyncHintHandler = @Sendable (ChatSyncHint) -> Void
    typealias ConnectedHandler = @Sendable () -> Void

    private let socket: any SparkWebSocketClientProtocol
    private let tokenProvider: AuthTokenProvider
    private let baseURL: URL
    private let logger: Logger

    private var isRunning = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var hintHandler: SyncHintHandler?
    private var connectedHandler: ConnectedHandler?

    init(
        socket: any SparkWebSocketClientProtocol = SparkWebSocketClient(),
        tokenProvider: AuthTokenProvider,
        baseURL: URL,
        logger: Logger = ConsoleLogger()
    ) {
        self.socket = socket
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.logger = logger
    }

    func start(onSyncHint: @escaping SyncHintHandler, onConnected: @escaping ConnectedHandler) async {
        hintHandler = onSyncHint
        connectedHandler = onConnected
        guard isRunning == false else { return }
        isRunning = true
        reconnectAttempt = 0
        await connectIfNeeded()
    }

    func stop() async {
        isRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        await socket.disconnect()
    }

    private func connectIfNeeded() async {
        guard isRunning else { return }

        do {
            var request = try await makeRequest()
            request.timeoutInterval = 20
            await socket.connect(request: request) { [weak self] event in
                guard let self else { return }
                Task {
                    await self.handle(event: event)
                }
            }
        } catch {
            // CHAT-000059 C-001/C-006：建连失败只作为实时通道失败，永远不触发全局鉴权失效。
            logger.warning(
                "chat realtime connect failed: \(error.localizedDescription) source=chat_realtime event=connect_failed auth_invalidation_emitted=false reconnect_scheduled=true",
                module: .general
            )
            scheduleReconnect()
        }
    }

    private func makeRequest() async throws -> URLRequest {
        let auth = try await tokenProvider.authorizationHeaderValue()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = "/ws/chat/sync/"

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        return request
    }

    private func handle(event: SparkWebSocketEvent) async {
        guard isRunning else { return }

        switch event {
        case .connected:
            reconnectAttempt = 0
            // CHAT-000056 Q3：WebSocket 每次连接成功（含首次与每次重连）都触发一次全局补偿。
            connectedHandler?()

        case .text(let text):
            // CHAT-000059 C-005：鉴权相关文本不做特殊处理；仅投递 chat.sync.updated。
            guard let data = text.data(using: .utf8) else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard let type = json["type"] as? String else { return }
            guard type == "chat.sync.updated" else { return }
            let hint = Self.parseHint(json: json, logger: logger)
            hintHandler?(hint)

        case .disconnected(let reason):
            // CHAT-000059 C-001：任意断开（含 Code=57、-1005、无 close code、4401 文本）只重连，不退出登录。
            logger.warning(
                "chat realtime disconnected: \(reason ?? "-") source=chat_realtime event=disconnected auth_invalidation_emitted=false reconnect_scheduled=true",
                module: .general
            )
            scheduleReconnect()
        }
    }

    /// 解析 `chat.sync.updated` 事件（v1/v2 兼容）。
    /// v2 事件缺少或携带非法 `thread_id` 时降级为 `threadID == nil`，由同步层走全局补偿。
    nonisolated static func parseHint(json: [String: Any], logger: Logger = ConsoleLogger()) -> ChatSyncHint {
        let payloadVersion = (json["payload_version"] as? NSNumber)?.intValue ?? 1
        let eventID = (json["event_id"] as? String).flatMap { UUID(uuidString: $0) }
        let cursor = json["cursor"] as? String
        let messageIDs = (json["message_ids"] as? [String]) ?? []
        let emittedAt = (json["emitted_at"] as? String).flatMap(Self.parseEmittedAt)

        var threadID: UUID?
        if payloadVersion >= 2 {
            if let rawThreadID = json["thread_id"] as? String, let parsed = UUID(uuidString: rawThreadID) {
                threadID = parsed
            } else {
                // 兼容规则：无法解析 thread_id 的 v2 事件记录脱敏错误并走全局补偿。
                logger.warning(
                    "chat.realtime.hint invalid_thread_id version=\(payloadVersion) event=\(eventID?.uuidString.prefix(8) ?? "-")",
                    module: .general
                )
            }
        }

        return ChatSyncHint(
            eventID: eventID,
            payloadVersion: payloadVersion,
            threadID: threadID,
            cursor: cursor,
            messageIDs: messageIDs,
            emittedAt: emittedAt
        )
    }

    private nonisolated static func parseEmittedAt(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard isRunning else { return }

        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delaySeconds = min(30, max(1, Int(pow(2.0, Double(attempt)))))

        reconnectTask = Task {
            defer { reconnectTask = nil }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await connectIfNeeded()
        }
    }
}
