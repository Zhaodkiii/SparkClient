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
            logger.warning("chat realtime connect failed: \(error.localizedDescription)", module: .general)
            if Self.shouldInvalidateSession(for: error.localizedDescription) {
                postAuthSessionInvalidation(message: error.localizedDescription, source: "ChatRealtimeSyncClient.connect")
                await stop()
                return
            }
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

        case .text(let text):
            guard let data = text.data(using: .utf8) else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard let type = json["type"] as? String else { return }

            if Self.shouldInvalidateSession(in: json) {
                let message = (json["msg"] as? String) ?? type
                postAuthSessionInvalidation(message: message, source: "ChatRealtimeSyncClient.text")
                await stop()
                return
            }

            if type == "chat.sync.updated" {
                let cursor = json["cursor"] as? String
                hintHandler?(cursor)
            }

        case .disconnected(let reason):
            logger.warning("chat realtime disconnected: \(reason ?? "-")", module: .general)
            if Self.shouldInvalidateSessionOnDisconnect(reason: reason) {
                let message = reason ?? "websocket_auth_close_4401"
                postAuthSessionInvalidation(message: message, source: "ChatRealtimeSyncClient.disconnected")
                await stop()
                return
            }
            scheduleReconnect()
        }
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

    private static func shouldInvalidateSession(in json: [String: Any]) -> Bool {
        let type = (json["type"] as? String) ?? ""
        if type == "auth.session.invalidated" || type.hasPrefix("device_session.") {
            return true
        }
        let message = (json["msg"] as? String) ?? ""
        return shouldInvalidateSession(for: message)
    }

    private static func shouldInvalidateSession(for message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return false }
        return AuthSessionInvalidation.shouldInvalidate(
            statusCode: 401,
            backendCode: nil,
            message: normalized
        )
    }

    private static func shouldInvalidateSessionOnDisconnect(reason: String?) -> Bool {
        guard let reason else {
            return false
        }
        if isWebSocketAuthCloseCode(reason) {
            return true
        }
        return shouldInvalidateSession(for: reason)
    }

    private static func isWebSocketAuthCloseCode(_ reason: String) -> Bool {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("4401")
    }

    private func postAuthSessionInvalidation(message: String, source: String) {
        AuthSessionInvalidation.postIfNeeded(
            statusCode: 401,
            backendCode: nil,
            message: message,
            source: source
        )
    }
}
