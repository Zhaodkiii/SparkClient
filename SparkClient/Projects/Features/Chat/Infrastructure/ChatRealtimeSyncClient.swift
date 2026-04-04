import Foundation

actor ChatRealtimeSyncClient {
    typealias SyncHintHandler = @Sendable (String?) -> Void

    private let socket: SparkWebSocketClient
    private let tokenProvider: AuthTokenProvider
    private let baseURL: URL
    private let logger: Logger

    private var isRunning = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var hintHandler: SyncHintHandler?

    init(
        socket: SparkWebSocketClient = SparkWebSocketClient(),
        tokenProvider: AuthTokenProvider,
        baseURL: URL,
        logger: Logger = ConsoleLogger()
    ) {
        self.socket = socket
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.logger = logger
    }

    func start(onSyncHint: @escaping SyncHintHandler) async {
        hintHandler = onSyncHint
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
            logger.warning("chat realtime connect failed: \(error.localizedDescription)", category: "chat_sync")
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
        // 与 HTTP 保持同一 JWT 来源，避免 WS 与 REST 看到不同登录态。
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        return request
    }

    private func handle(event: SparkWebSocketEvent) async {
        guard isRunning else { return }

        switch event {
        case .connected:
            reconnectAttempt = 0
            hintHandler?(nil)

        case .text(let text):
            guard let data = text.data(using: .utf8) else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard let type = json["type"] as? String else { return }

            if type == "chat.sync.updated" {
                let cursor = json["cursor"] as? String
                hintHandler?(cursor)
            } else if type == "chat.sync.connected" {
                hintHandler?(nil)
            }

        case .disconnected(let reason):
            logger.warning("chat realtime disconnected: \(reason ?? "-")", category: "chat_sync")
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard isRunning else { return }

        let attempt = reconnectAttempt
        reconnectAttempt += 1
        // 指数退避，避免网络抖动时频繁重连打爆服务端。
        let delaySeconds = min(30, max(1, Int(pow(2.0, Double(attempt)))))

        reconnectTask = Task {
            defer { reconnectTask = nil }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await connectIfNeeded()
        }
    }
}
