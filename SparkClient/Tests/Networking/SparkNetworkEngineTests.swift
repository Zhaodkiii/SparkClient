#if canImport(XCTest)
import XCTest

final class SparkNetworkEngineTests: XCTestCase {
    // MARK: - URLProtocol Stub

    private struct StubHTTPResponse {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
    }

    private final class URLProtocolStub: URLProtocol {
        static var requestHandler: ((URLRequest) -> StubHTTPResponse)?
        static var requestCountLock = NSLock()
        static var requestCount: Int = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            URLProtocolStub.requestCountLock.lock()
            URLProtocolStub.requestCount += 1
            URLProtocolStub.requestCountLock.unlock()

            guard let handler = URLProtocolStub.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            let stub = handler(request)
            let url = request.url ?? URL(string: "http://localhost")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!

            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            requestHandler = nil
            requestCountLock.lock()
            requestCount = 0
            requestCountLock.unlock()
        }
    }

    private func makeBackendWrappedJSON<T: Encodable>(data: T) throws -> Data {
        struct Wrapped: Encodable {
            let code: Int
            let msg: String
            let data: T
        }
        let wrapped = Wrapped(code: 0, msg: "ok", data: data)
        return try JSONEncoder().encode(wrapped)
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
            "sub": sub
        ]

        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        let headerB64 = base64URLEncode(headerData)
        let payloadB64 = base64URLEncode(payloadData)
        return "\(headerB64).\(payloadB64).signature"
    }

    // MARK: - Tests

    struct ETagPayload: Decodable, Equatable {
        let value: Int
    }

    func testETag304MergesCachedBody() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = FileETagStore(baseDirectory: tmpDir)
        let interceptor = ETagHTTPInterceptor(store: store)

        // Precompute the same cache key engine will use (URL + Authorization header).
        let urlRequest = URLRequest(url: baseURL.appendingPathComponent("etag/test"))
        let cacheKey = interceptor.cacheKey(for: urlRequest)
        try store.store(etag: "test-etag", body: try makeBackendWrappedJSON(data: ETagPayload(value: 1)), forKey: cacheKey)

        URLProtocolStub.requestHandler = { req in
            let ifNoneMatch = req.value(forHTTPHeaderField: "If-None-Match")
            XCTAssertEqual(ifNoneMatch, "test-etag")

            let url = req.url!.absoluteString
            let responseBody = Data() // will be replaced by cached body

            return StubHTTPResponse(statusCode: 304, headers: [:], body: responseBody)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())

        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: interceptor,
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        let request = SparkNetworkRequest(
            method: .get,
            path: "/etag/test",
            queryItems: nil,
            headers: [:],
            body: .none,
            timeoutInterval: nil,
            strategy: NetworkStrategy(
                requiresAuth: false,
                allowETag: true,
                serialKey: "etag.test",
                retryConfig: RetryConfig(isEnabled: false, maxRetryCount: 0, retryableStatusCodes: [], retryableURLErrorCodes: [], honorsRetryAfter: true, backoffIntervals: [0]),
                isIdempotent: true
            )
        )

        let payload: ETagPayload = try await engine.send(request, decodingMode: .backendWrapped)
        XCTAssertEqual(payload, ETagPayload(value: 1))
    }

    func testExpiredETagDoesNotAttachIfNoneMatch() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = FileETagStore(baseDirectory: tmpDir)
        let interceptor = ETagHTTPInterceptor(store: store)
        let urlRequest = URLRequest(url: baseURL.appendingPathComponent("etag/expired"))
        let cacheKey = interceptor.cacheKey(for: urlRequest)

        try store.store(
            record: ETagCacheRecord(
                etag: "expired-etag",
                lastUpdated: Date().addingTimeInterval(-300),
                expirationDate: Date().addingTimeInterval(-60)
            ),
            body: try makeBackendWrappedJSON(data: ETagPayload(value: 9)),
            forKey: cacheKey
        )

        URLProtocolStub.requestHandler = { req in
            XCTAssertNil(req.value(forHTTPHeaderField: "If-None-Match"))
            let data = try! self.makeBackendWrappedJSON(data: ETagPayload(value: 2))
            return StubHTTPResponse(statusCode: 200, headers: ["ETag": "fresh"], body: data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())

        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: interceptor,
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        let request = SparkNetworkRequest(
            method: .get,
            path: "/etag/expired",
            strategy: NetworkStrategy(
                requiresAuth: false,
                allowETag: true,
                serialKey: "etag.expired",
                retryConfig: .default,
                isIdempotent: true,
                queuePriority: .normal,
                etagTTL: 30
            )
        )

        let payload: ETagPayload = try await engine.send(request, decodingMode: .backendWrapped)
        XCTAssertEqual(payload, ETagPayload(value: 2))
    }

    func testETagRequestUploadsCacheMaxAge() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())
        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: tmpDir)),
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Cache-Max-Age"), "86400")
            let data = try! self.makeBackendWrappedJSON(data: ETagPayload(value: 3))
            return StubHTTPResponse(statusCode: 200, headers: ["ETag": "fresh"], body: data)
        }

        let request = SparkNetworkRequest(
            method: .get,
            path: "/etag/cache-max-age",
            strategy: NetworkStrategy(
                requiresAuth: false,
                allowETag: true,
                serialKey: "etag.cache_max_age",
                retryConfig: .default,
                isIdempotent: true,
                queuePriority: .normal,
                etagTTL: 86400
            )
        )

        let payload: ETagPayload = try await engine.send(request, decodingMode: .backendWrapped)
        XCTAssertEqual(payload, ETagPayload(value: 3))
    }

    func testETagRequestDoesNotOverrideCustomCacheMaxAgeHeader() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())
        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: tmpDir)),
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Cache-Max-Age"), "3600")
            let data = try! self.makeBackendWrappedJSON(data: ETagPayload(value: 4))
            return StubHTTPResponse(statusCode: 200, headers: ["ETag": "fresh"], body: data)
        }

        let request = SparkNetworkRequest(
            method: .get,
            path: "/etag/custom-cache-max-age",
            headers: ["X-Cache-Max-Age": "3600"],
            strategy: NetworkStrategy(
                requiresAuth: false,
                allowETag: true,
                serialKey: "etag.custom_cache_max_age",
                retryConfig: .default,
                isIdempotent: true,
                queuePriority: .normal,
                etagTTL: 86400
            )
        )

        let payload: ETagPayload = try await engine.send(request, decodingMode: .backendWrapped)
        XCTAssertEqual(payload, ETagPayload(value: 4))
    }

    actor SleepRecorder {
        var slept: [TimeInterval] = []
        func record(_ seconds: TimeInterval) {
            slept.append(seconds)
        }
    }

    struct RecordingScheduler: RetryScheduler {
        let recorder: SleepRecorder
        func sleep(for seconds: TimeInterval) async throws {
            await recorder.record(seconds)
        }
    }

    struct RetryAfterPayload: Decodable, Equatable {
        let ok: Bool
    }

    func testRetryAfterSleepsAndRetries() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configLock = NSLock()
        var protectedCalls = 0

        URLProtocolStub.requestHandler = { req in
            configLock.lock()
            protectedCalls += 1
            let callIndex = protectedCalls
            configLock.unlock()

            if callIndex == 1 {
                let body = Data() // not needed; engine will retry
                return StubHTTPResponse(statusCode: 429, headers: ["Retry-After": "1"], body: body)
            }

            let data = try! self.makeBackendWrappedJSON(data: RetryAfterPayload(ok: true))
            return StubHTTPResponse(statusCode: 200, headers: [:], body: data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())

        let recorder = SleepRecorder()
        let scheduler = RecordingScheduler(recorder: recorder)
        let engineRetryPolicy = RetryPolicy(config: .default, scheduler: scheduler)

        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: tmpDir)),
            retryPolicy: engineRetryPolicy,
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        let request = SparkNetworkRequest(
            method: .get,
            path: "/retry/test",
            queryItems: nil,
            headers: [:],
            body: .none,
            timeoutInterval: nil,
            strategy: NetworkStrategy(
                requiresAuth: false,
                allowETag: false,
                serialKey: "retry.test",
                retryConfig: RetryConfig(
                    isEnabled: true,
                    maxRetryCount: 1,
                    retryableStatusCodes: [429],
                    retryableURLErrorCodes: [],
                    honorsRetryAfter: true,
                    backoffIntervals: [0]
                ),
                isIdempotent: true
            )
        )

        let payload: RetryAfterPayload = try await engine.send(request)
        XCTAssertEqual(payload, RetryAfterPayload(ok: true))

        let slept = await recorder.slept
        XCTAssertEqual(slept, [1])
    }

    actor EventRecorder {
        var events: [String] = []
        func add(_ event: String) { events.append(event) }
        func snapshot() -> [String] { events }
    }

    final class AsyncLatch {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }
        func signal() {
            for w in waiters { w.resume() }
            waiters.removeAll()
        }
    }

    func testSerialRequestGateFIFOAndRetryPriority() async throws {
        let gate = SerialRequestGate()
        let recorder = EventRecorder()
        let latch = AsyncLatch()

        async let taskA: Void = gate.enqueue(serialKey: "k", priority: .normal) {
            await latch.wait()
            await recorder.add("A")
        }
        // Give A a chance to start and block.
        await Task.yield()

        async let taskB: Void = gate.enqueue(serialKey: "k", priority: .normal) {
            await recorder.add("B")
        }

        async let taskC: Void = gate.enqueue(serialKey: "k", priority: .normal) {
            await recorder.add("C")
        }

        async let taskRetry: Void = gate.enqueue(serialKey: "k", priority: .retry) {
            await recorder.add("Retry")
        }

        latch.signal()
        _ = try await (taskA, taskB, taskC, taskRetry)

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["A", "Retry", "B", "C"])
    }

    func testSerialRequestGateHighPriorityRunsBeforeNormal() async throws {
        let gate = SerialRequestGate()
        let recorder = EventRecorder()
        let latch = AsyncLatch()

        async let first: Void = gate.enqueue(serialKey: "priority", priority: .normal) {
            await latch.wait()
            await recorder.add("First")
        }
        await Task.yield()

        async let normal: Void = gate.enqueue(serialKey: "priority", priority: .normal) {
            await recorder.add("Normal")
        }

        async let high: Void = gate.enqueue(serialKey: "priority", priority: .high) {
            await recorder.add("High")
        }

        latch.signal()
        _ = try await (first, normal, high)

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["First", "High", "Normal"])
    }

    func testConcurrent401TriggersSingleRefresh() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let lock = NSLock()
        var refreshCalls = 0
        var protectedCalls = 0

        let accessJWT = makeFakeJWT(expDate: Date().addingTimeInterval(3600), sub: "u1")
        let refreshJWT = makeFakeJWT(expDate: Date().addingTimeInterval(7200), sub: "u1")

        URLProtocolStub.requestHandler = { req in
            let url = req.url!.absoluteString
            lock.lock()
            if url.contains("/api/v1/auth/token/refresh/") {
                refreshCalls += 1
                lock.unlock()

                let body = """
                {"access":"\(accessJWT)","refresh":"\(refreshJWT)"}
                """
                .data(using: .utf8)!
                return StubHTTPResponse(statusCode: 200, headers: [:], body: body)
            }

            if url.contains("/api/v1/test/protected/") {
                protectedCalls += 1
                let shouldFail = refreshCalls == 0
                lock.unlock()

                if shouldFail {
                    return StubHTTPResponse(statusCode: 401, headers: [:], body: Data())
                }

                struct Protected: Encodable { let ok: Bool }
                let data = try! self.makeBackendWrappedJSON(data: Protected(ok: true))
                return StubHTTPResponse(statusCode: 200, headers: [:], body: data)
            }

            lock.unlock()
            return StubHTTPResponse(statusCode: 404, headers: [:], body: Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())

        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: FileManager.default.temporaryDirectory)),
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        struct ProtectedResponse: Decodable, Equatable {
            let ok: Bool
        }

        let request1 = SparkNetworkRequest(
            method: .get,
            path: "/api/v1/test/protected/",
            queryItems: nil,
            headers: [:],
            body: .none,
            timeoutInterval: nil,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: false, serialKey: "p1", retryConfig: RetryConfig.default, isIdempotent: true)
        )
        let request2 = SparkNetworkRequest(
            method: .get,
            path: "/api/v1/test/protected/",
            queryItems: nil,
            headers: [:],
            body: .none,
            timeoutInterval: nil,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: false, serialKey: "p2", retryConfig: RetryConfig.default, isIdempotent: true)
        )

        // Ensure provider has a refresh token to use; refreshTokensDeDuplicated will read it from keychain.
        // For tests without keychain setup, we simulate by setting tokens via provider directly.
        let initialTokens = AuthTokens(
            accessToken: accessJWT,
            refreshToken: refreshJWT,
            expiresAt: Date().addingTimeInterval(-10), // force refresh on first 401
            tokenType: "Bearer"
        )
        await engine.tokenProvider().setTokens(initialTokens)

        async let result1: ProtectedResponse = engine.send(request1)
        async let result2: ProtectedResponse = engine.send(request2)

        let (r1, r2) = try await (result1, result2)
        XCTAssertEqual(r1, ProtectedResponse(ok: true))
        XCTAssertEqual(r2, ProtectedResponse(ok: true))

        lock.lock()
        let refreshCount = refreshCalls
        lock.unlock()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertGreaterThanOrEqual(protectedCalls, 2)
    }

    func testRefresh401PostsAuthInvalidationNotification() async throws {
        URLProtocolStub.reset()

        let baseURL = URL(string: "http://localhost")!
        let accessJWT = makeFakeJWT(expDate: Date().addingTimeInterval(3600), sub: "u1")
        let refreshJWT = makeFakeJWT(expDate: Date().addingTimeInterval(7200), sub: "u1")

        URLProtocolStub.requestHandler = { req in
            let url = req.url!.absoluteString
            if url.contains("/api/v1/auth/token/refresh/") {
                let body = """
                {"code":40102,"msg":"token_not_valid","data":{"request_id":"test-refresh-401"}}
                """
                .data(using: .utf8)!
                return StubHTTPResponse(statusCode: 401, headers: [:], body: body)
            }

            if url.contains("/api/v1/test/protected/") {
                let body = """
                {"code":-1,"msg":{"detail":"User not found","code":"user_not_found"},"data":{"request_id":"test-protected-401"}}
                """
                .data(using: .utf8)!
                return StubHTTPResponse(statusCode: 401, headers: [:], body: body)
            }

            return StubHTTPResponse(statusCode: 404, headers: [:], body: Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())

        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: SerialRequestGate(),
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: FileManager.default.temporaryDirectory)),
            retryPolicy: RetryPolicy(config: .default, scheduler: DefaultRetryScheduler()),
            authProvider: AuthTokenProvider(transport: transport, baseURL: baseURL, logger: ConsoleLogger())
        )

        await engine.tokenProvider().setTokens(
            AuthTokens(
                accessToken: accessJWT,
                refreshToken: refreshJWT,
                expiresAt: Date().addingTimeInterval(3600),
                tokenType: "Bearer"
            )
        )

        let invalidation = expectation(forNotification: AuthSessionInvalidation.notificationName, object: nil) { notification in
            notification.userInfo?["source"] as? String == "SparkNetworkEngine.sendRaw.refreshFailed"
        }

        struct ProtectedResponse: Decodable {
            let ok: Bool
        }

        let request = SparkNetworkRequest(
            method: .get,
            path: "/api/v1/test/protected/",
            queryItems: nil,
            headers: [:],
            body: .none,
            timeoutInterval: nil,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: false, serialKey: "refresh-401", retryConfig: RetryConfig.default, isIdempotent: true)
        )

        do {
            let _: ProtectedResponse = try await engine.send(request)
            XCTFail("Expected refresh failure")
        } catch SparkNetworkError.refreshFailed {
            // Expected.
        } catch {
            XCTFail("Expected SparkNetworkError.refreshFailed, got \(error)")
        }

        await fulfillment(of: [invalidation], timeout: 1.0)
    }
}

#endif
