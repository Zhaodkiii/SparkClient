#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000059：WebSocket 实时通道不得触发全局鉴权失效。
final class ChatRealtimeSyncClientTests: XCTestCase {
    func testConnectFailureDoesNotInvalidateSessionAndSchedulesReconnect() async {
        let socket = FakeSparkWebSocketClient()
        let tokenProvider = makeTokenProvider()
        defer { Task { await tokenProvider.clearTokens() } }

        let client = ChatRealtimeSyncClient(
            socket: socket,
            tokenProvider: tokenProvider,
            baseURL: URL(string: "https://example.test")!,
            logger: ConsoleLogger()
        )

        let invalidation = invertedInvalidationExpectation()
        await client.start(onSyncHint: { _ in }, onConnected: {})

        XCTAssertEqual(await socket.connectCount, 0, "无 Token 时不得发起 WebSocket connect")

        await tokenProvider.setTokens(makeValidTokens())
        let reconnected = await waitUntil { await socket.connectCount >= 1 }
        XCTAssertTrue(reconnected, "建连失败后应退避重连，补齐 Token 后调用 socket.connect")

        await fulfillment(of: [invalidation], timeout: 0.4)
        await client.stop()
    }

    func testDisconnectedWithTransportReasonsDoesNotInvalidateSession() async {
        let reasons: [String?] = [
            "NSPOSIXErrorDomain Code=57 Socket is not connected",
            "NSURLErrorDomain Code=-1005 网络连接已中断",
            nil,
            "websocket close code 4401",
        ]

        for reason in reasons {
            let fixture = await makeConnectedFixture()
            defer { Task { await fixture.tokenProvider.clearTokens() } }

            let invalidation = invertedInvalidationExpectation()
            await fixture.socket.emit(.disconnected(reason))

            let reconnected = await waitUntil { await fixture.socket.connectCount >= 2 }
            XCTAssertTrue(reconnected, "断开后应调度重连，reason=\(reason ?? "nil")")
            await fulfillment(of: [invalidation], timeout: 0.4)
            await fixture.client.stop()
        }
    }

    func testAuthRelatedTextDoesNotInvalidateSessionOrDeliverHint() async {
        let fixture = await makeConnectedFixture()
        defer { Task { await fixture.tokenProvider.clearTokens() } }

        let hintRecorder = HintRecorder()
        await fixture.client.start(
            onSyncHint: { hint in
                Task { await hintRecorder.append(hint) }
            },
            onConnected: {}
        )

        let payloads = [
            #"{"type":"auth.session.invalidated","msg":"token_not_valid"}"#,
            #"{"type":"device_session.revoked","msg":"device_session_revoked"}"#,
            #"{"type":"notice","msg":"given token not valid"}"#,
        ]

        let invalidation = invertedInvalidationExpectation()
        for payload in payloads {
            await fixture.socket.emit(.text(payload))
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        let hints = await hintRecorder.hints
        XCTAssertTrue(hints.isEmpty, "鉴权相关文本不得当作 chat.sync.updated 投递")
        await fulfillment(of: [invalidation], timeout: 0.4)
        await fixture.client.stop()
    }

    func testChatSyncUpdatedStillDeliversHint() async {
        let fixture = await makeConnectedFixture()
        defer { Task { await fixture.tokenProvider.clearTokens() } }

        let hintRecorder = HintRecorder()
        await fixture.client.start(
            onSyncHint: { hint in
                Task { await hintRecorder.append(hint) }
            },
            onConnected: {}
        )

        let payload = #"{"type":"chat.sync.updated","cursor":"v2:abc","message_ids":["m-1"]}"#
        await fixture.socket.emit(.text(payload))

        let delivered = await waitUntil { await hintRecorder.hints.isEmpty == false }
        XCTAssertTrue(delivered)
        let hints = await hintRecorder.hints
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.cursor, "v2:abc")
        XCTAssertEqual(hints.first?.messageIDs, ["m-1"])
        await fixture.client.stop()
    }

    func testConnectedResetsReconnectAttemptAndInvokesHandler() async {
        let fixture = await makeConnectedFixture()
        defer { Task { await fixture.tokenProvider.clearTokens() } }

        let connected = ConnectedRecorder()
        await fixture.client.start(
            onSyncHint: { _ in },
            onConnected: {
                Task { await connected.mark() }
            }
        )

        await fixture.socket.emit(.connected)
        let invoked = await waitUntil { await connected.didConnect }
        XCTAssertTrue(invoked)

        await fixture.socket.emit(.disconnected("Socket is not connected"))
        let reconnected = await waitUntil { await fixture.socket.connectCount >= 2 }
        XCTAssertTrue(reconnected)

        await fixture.socket.emit(.connected)
        let invokedAgain = await waitUntil { await connected.count >= 2 }
        XCTAssertTrue(invokedAgain)
        await fixture.client.stop()
    }

    // MARK: - 辅助

    private struct Fixture {
        let client: ChatRealtimeSyncClient
        let socket: FakeSparkWebSocketClient
        let tokenProvider: AuthTokenProvider
    }

    private func makeConnectedFixture() async -> Fixture {
        let socket = FakeSparkWebSocketClient()
        let tokenProvider = makeTokenProvider()
        await tokenProvider.setTokens(makeValidTokens())
        let client = ChatRealtimeSyncClient(
            socket: socket,
            tokenProvider: tokenProvider,
            baseURL: URL(string: "https://example.test")!,
            logger: ConsoleLogger()
        )
        await client.start(onSyncHint: { _ in }, onConnected: {})
        let connected = await waitUntil { await socket.connectCount >= 1 }
        XCTAssertTrue(connected, "start 后应调用 socket.connect")
        return Fixture(client: client, socket: socket, tokenProvider: tokenProvider)
    }

    private func makeTokenProvider() -> AuthTokenProvider {
        AuthTokenProvider(
            transport: FailingSparkNetworkTransport(),
            baseURL: URL(string: "https://example.test")!,
            keychainService: "SparkClient.Auth.ChatRealtimeTests.\(UUID().uuidString)",
            logger: ConsoleLogger()
        )
    }

    private func makeValidTokens() -> AuthTokens {
        AuthTokens(
            accessToken: makeFakeJWT(expDate: Date().addingTimeInterval(3600)),
            refreshToken: makeFakeJWT(expDate: Date().addingTimeInterval(7200)),
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer"
        )
    }

    private func makeFakeJWT(expDate: Date, sub: String = "user") -> String {
        func base64URLEncode(_ data: Data) -> String {
            var str = data.base64EncodedString()
            str = str.replacingOccurrences(of: "+", with: "-")
            str = str.replacingOccurrences(of: "/", with: "_")
            str = str.replacingOccurrences(of: "=", with: "")
            return str
        }

        let header: [String: String] = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "exp": Int(expDate.timeIntervalSince1970),
            "sub": sub,
        ]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        return "\(base64URLEncode(headerData)).\(base64URLEncode(payloadData)).signature"
    }

    private func invertedInvalidationExpectation() -> XCTestExpectation {
        let expectation = expectation(forNotification: AuthSessionInvalidation.notificationName, object: nil)
        expectation.isInverted = true
        return expectation
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}

private actor FakeSparkWebSocketClient: SparkWebSocketClientProtocol {
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private var eventHandler: (@Sendable (SparkWebSocketEvent) -> Void)?

    func connect(request: URLRequest, eventHandler: @escaping @Sendable (SparkWebSocketEvent) -> Void) {
        connectCount += 1
        self.eventHandler = eventHandler
    }

    func send(text: String) async {}

    func disconnect() {
        disconnectCount += 1
        eventHandler = nil
    }

    func emit(_ event: SparkWebSocketEvent) {
        eventHandler?(event)
    }
}

private struct FailingSparkNetworkTransport: SparkNetworkTransport {
    func send(_ urlRequest: URLRequest) async throws -> SparkTransportResponse {
        throw URLError(.notConnectedToInternet)
    }
}

private actor HintRecorder {
    private(set) var hints: [ChatSyncHint] = []

    func append(_ hint: ChatSyncHint) {
        hints.append(hint)
    }
}

private actor ConnectedRecorder {
    private(set) var count = 0

    var didConnect: Bool { count > 0 }

    func mark() {
        count += 1
    }
}
#endif
