#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000056：实时 hint 解析契约（16.1 兼容规则）。
final class ChatSyncHintParsingTests: XCTestCase {
    func testV1HintWithoutThreadIDParsesAsGlobalCompensationHint() {
        let json: [String: Any] = [
            "type": "chat.sync.updated",
            "cursor": "2026-09-02T10:00:00Z",
            "message_ids": ["m-1", "m-2"],
        ]

        let hint = ChatRealtimeSyncClient.parseHint(json: json, logger: NullLogger())

        XCTAssertEqual(hint.payloadVersion, 1)
        XCTAssertNil(hint.threadID)
        XCTAssertEqual(hint.cursor, "2026-09-02T10:00:00Z")
        XCTAssertEqual(hint.messageIDs, ["m-1", "m-2"])
    }

    func testV2HintParsesAllStructuredFields() {
        let threadID = UUID()
        let eventID = UUID()
        let json: [String: Any] = [
            "type": "chat.sync.updated",
            "payload_version": 2,
            "event_id": eventID.uuidString,
            "thread_id": threadID.uuidString,
            "cursor": "v2:abc",
            "message_ids": ["m-9"],
            "emitted_at": "2026-09-02T10:00:00.123Z",
        ]

        let hint = ChatRealtimeSyncClient.parseHint(json: json, logger: NullLogger())

        XCTAssertEqual(hint.payloadVersion, 2)
        XCTAssertEqual(hint.eventID, eventID)
        XCTAssertEqual(hint.threadID, threadID)
        XCTAssertEqual(hint.cursor, "v2:abc")
        XCTAssertEqual(hint.messageIDs, ["m-9"])
        XCTAssertNotNil(hint.emittedAt)
    }

    func testV2HintWithUnparseableThreadIDDegeneratesToGlobalCompensation() {
        let json: [String: Any] = [
            "type": "chat.sync.updated",
            "payload_version": 2,
            "thread_id": "not-a-uuid",
        ]

        let hint = ChatRealtimeSyncClient.parseHint(json: json, logger: NullLogger())

        XCTAssertEqual(hint.payloadVersion, 2)
        XCTAssertNil(hint.threadID)
    }

    func testV2HintWithoutThreadIDDegeneratesToGlobalCompensation() {
        let json: [String: Any] = [
            "type": "chat.sync.updated",
            "payload_version": 2,
        ]

        let hint = ChatRealtimeSyncClient.parseHint(json: json, logger: NullLogger())

        XCTAssertNil(hint.threadID)
    }
}

/// CHAT-000056 Q4/Q9/Q3：per-thread 调度、dirty 重拉、分类重试与全局补偿状态机。
final class ChatRealtimePullSchedulerTests: XCTestCase {
    private let threadA = UUID()
    private let threadB = UUID()

    func testHintWithoutThreadTriggersGlobalCompensation() async {
        let recorder = PullRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: nil))

        let reached = await waitUntil { await recorder.globalCallCount == 1 }
        XCTAssertTrue(reached)
        let threadCalls = await recorder.threadCalls
        XCTAssertTrue(threadCalls.isEmpty)
    }

    func testV2HintPullsTargetThreadAfterDebounce() async {
        let recorder = PullRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: threadA))

        let reached = await waitUntil { await recorder.threadCalls.count == 1 }
        XCTAssertTrue(reached)
        let calls = await recorder.threadCalls
        XCTAssertEqual(calls.first?.0, threadA)
        XCTAssertEqual(calls.first?.1, false)
    }

    func testHintDuringThreadPullMarksDirtyAndRepullsOnce() async {
        let recorder = PullRecorder()
        let gate = PullGate()
        let scheduler = makeScheduler(
            recorder: recorder,
            threadPullGate: gate
        )

        await scheduler.handleHint(makeHint(threadID: threadA))
        // 等第一次拉取开始（被 gate 卡住）。
        let started = await waitUntil { await recorder.threadCalls.count == 1 }
        XCTAssertTrue(started)

        // pulling 期间到达的同 thread hint 只标 dirty。
        await scheduler.handleHint(makeHint(threadID: threadA))
        await scheduler.handleHint(makeHint(threadID: threadA))

        await gate.open()

        // dirty → 立即补拉一次；两条 dirty hint 合并为一轮。
        let repulled = await waitUntil { await recorder.threadCalls.count == 2 }
        XCTAssertTrue(repulled)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let calls = await recorder.threadCalls
        XCTAssertEqual(calls.count, 2)
    }

    func testHintsForDifferentThreadsPullIndependently() async {
        let recorder = PullRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: threadA))
        await scheduler.handleHint(makeHint(threadID: threadB))

        let reached = await waitUntil { await recorder.threadCalls.count == 2 }
        XCTAssertTrue(reached)
        let pulled = await recorder.threadCalls.map { $0.0 }
        XCTAssertTrue(pulled.contains(threadA))
        XCTAssertTrue(pulled.contains(threadB))
    }

    func testHintDuringGlobalCompensationIsDrainedToThreadPull() async {
        let recorder = PullRecorder()
        let gate = PullGate()
        let scheduler = makeScheduler(recorder: recorder, globalPullGate: gate)

        await scheduler.requestGlobalCompensation(source: .realtimeConnected)
        let globalStarted = await waitUntil { await recorder.globalCallCount == 1 }
        XCTAssertTrue(globalStarted)

        // 全局运行期间到达的 thread hint 不得被吞掉。
        await scheduler.handleHint(makeHint(threadID: threadA))
        try? await Task.sleep(nanoseconds: 100_000_000)
        var calls = await recorder.threadCalls
        XCTAssertTrue(calls.isEmpty)

        await gate.open()
        let drained = await waitUntil { await recorder.threadCalls.contains { $0.0 == self.threadA } }
        XCTAssertTrue(drained)
        calls = await recorder.threadCalls
        XCTAssertEqual(calls.filter { $0.0 == threadA }.count, 1)
    }

    func testConcurrentGlobalTriggersCoalesceWithDirtyRerun() async {
        let recorder = PullRecorder()
        let gate = PullGate()
        let scheduler = makeScheduler(recorder: recorder, globalPullGate: gate)

        await scheduler.requestGlobalCompensation(source: .accountStartup)
        let started = await waitUntil { await recorder.globalCallCount == 1 }
        XCTAssertTrue(started)

        await scheduler.requestGlobalCompensation(source: .foreground)
        await scheduler.requestGlobalCompensation(source: .networkRecovered)

        await gate.open()

        let rerun = await waitUntil { await recorder.globalCallCount >= 2 }
        XCTAssertTrue(rerun)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let count = await recorder.globalCallCount
        XCTAssertEqual(count, 2, "多个并发触发只应合并出一轮 dirty 重跑")
    }

    func testRetryableErrorRetriesAndSucceedsWithoutClearingCursor() async {
        let recorder = PullRecorder()
        recorder.threadFailures = [TestSyncError.retryable]
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: threadA))

        let retried = await waitUntil { await recorder.threadCalls.count == 2 }
        XCTAssertTrue(retried)
        let calls = await recorder.threadCalls
        XCTAssertEqual(calls.map { $0.1 }, [false, false], "网络类错误不得触发全量重拉")
    }

    func testCursorInvalidErrorFullRepullsOnlyThatThread() async {
        let recorder = PullRecorder()
        recorder.threadFailures = [TestSyncError.cursorInvalid]
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: threadA))
        await scheduler.handleHint(makeHint(threadID: threadB))

        let repulled = await waitUntil { await recorder.threadCalls.filter { $0.0 == self.threadA }.count == 2 }
        XCTAssertTrue(repulled)
        let callsA = await recorder.threadCalls.filter { $0.0 == threadA }
        XCTAssertEqual(callsA.map { $0.1 }, [false, true], "cursor 失效仅对该 thread 全量重拉")
        let callsB = await recorder.threadCalls.filter { $0.0 == threadB }
        XCTAssertEqual(callsB.map { $0.1 }, [false], "其他 thread 不受影响")
    }

    func testRetryExhaustionStopsAndNextHintRetriggers() async {
        let recorder = PullRecorder()
        recorder.threadFailures = [TestSyncError.retryable, .retryable, .retryable, .retryable]
        let scheduler = makeScheduler(recorder: recorder, maxRetryAttempts: 2)

        await scheduler.handleHint(makeHint(threadID: threadA))
        let exhausted = await waitUntil { await recorder.threadCalls.count == 3 }
        XCTAssertTrue(exhausted, "1 次原始拉取 + 2 次重试后应停止")

        try? await Task.sleep(nanoseconds: 200_000_000)
        var calls = await recorder.threadCalls
        XCTAssertEqual(calls.count, 3)

        // 达到上限后保持 dirty：新 hint 重新激活拉取。
        await scheduler.handleHint(makeHint(threadID: threadA))
        let retriggered = await waitUntil { await recorder.threadCalls.count == 4 }
        XCTAssertTrue(retriggered)
        calls = await recorder.threadCalls
        XCTAssertEqual(calls.count, 4)
    }

    func testThreadMissingStopsRetryingThatThread() async {
        let recorder = PullRecorder()
        recorder.threadFailures = [TestSyncError.threadMissing]
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.handleHint(makeHint(threadID: threadA))
        let pulled = await waitUntil { await recorder.threadCalls.count == 1 }
        XCTAssertTrue(pulled)

        try? await Task.sleep(nanoseconds: 300_000_000)
        let calls = await recorder.threadCalls
        XCTAssertEqual(calls.count, 1, "thread 404 不得自动重试")
    }

    // MARK: - 测试辅助

    private func makeScheduler(
        recorder: PullRecorder,
        threadPullGate: PullGate? = nil,
        globalPullGate: PullGate? = nil,
        maxRetryAttempts: Int = 3
    ) -> ChatRealtimePullScheduler {
        ChatRealtimePullScheduler(
            config: .init(
                debounceNanoseconds: 10_000_000,
                maxRetryAttempts: maxRetryAttempts,
                retryBaseDelayNanoseconds: 10_000_000,
                retryMaxDelayNanoseconds: 40_000_000,
                maxGlobalExtraCycles: 3
            ),
            pullThread: { threadID, forceFull in
                if let threadPullGate {
                    await threadPullGate.wait()
                }
                await recorder.recordThreadCall(threadID: threadID, forceFull: forceFull)
            },
            pullGlobal: {
                if let globalPullGate {
                    await globalPullGate.wait()
                }
                await recorder.recordGlobalCall()
            },
            classifyError: { error in
                guard let testError = error as? TestSyncError else { return .terminal }
                switch testError {
                case .retryable: return .retryable
                case .cursorInvalid: return .cursorInvalid
                case .threadMissing: return .threadMissing
                }
            },
            logger: NullLogger()
        )
    }

    private func makeHint(threadID: UUID?) -> ChatSyncHint {
        ChatSyncHint(
            eventID: UUID(),
            payloadVersion: threadID == nil ? 1 : 2,
            threadID: threadID,
            cursor: nil,
            messageIDs: [],
            emittedAt: nil
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }
}

private enum TestSyncError: Error {
    case retryable
    case cursorInvalid
    case threadMissing
}

private final class PullRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _threadCalls: [(UUID, Bool)] = []
    private var _globalCallCount = 0
    /// 按调用顺序弹出的失败队列；空队列表示成功。
    var threadFailures: [TestSyncError] = [] {
        didSet { lock.unlock() }
    }

    init() {}

    var threadCalls: [(UUID, Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return _threadCalls
    }

    var globalCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _globalCallCount
    }

    func recordThreadCall(threadID: UUID, forceFull: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        _threadCalls.append((threadID, forceFull))
        if threadFailures.isEmpty == false {
            let failure = threadFailures.removeFirst()
            throw failure
        }
    }

    func recordGlobalCall() {
        lock.lock()
        defer { lock.unlock() }
        _globalCallCount += 1
    }

    // 简化：willSet 里加锁，didSet 里解锁。
    var threadFailuresWillSetGuard = 0
}

private actor PullGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}
#endif
