#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000041：公共 Thread 获取/创建编排器测试（复用语义、单飞并发、模型门控）。
@MainActor
final class ChatThreadAcquisitionCoordinatorTests: XCTestCase {
    func testReusesLatestUnstartedWithoutCreating() async {
        let stateStore = ChatStateStore()
        let item = makeItem(memberID: 7, latestMessageAt: Date().addingTimeInterval(-301), hasUserMessage: false)
        stateStore.setThreads([item])
        let counter = AcquireTestCounter()

        let result = await makeCoordinator(stateStore: stateStore, counter: counter).acquire(
            accountID: 1,
            memberID: 7,
            hasAvailableChatModel: { true }
        )

        XCTAssertEqual(result, .reuse(threadID: item.id, reason: .latestUnstarted))
        XCTAssertEqual(counter.value, 0)
    }

    func testCreatesWhenLatestThreadHasUserMessage() async {
        let stateStore = ChatStateStore()
        let item = makeItem(memberID: 7, latestMessageAt: Date().addingTimeInterval(-301), hasUserMessage: true)
        stateStore.setThreads([item])
        let counter = AcquireTestCounter()
        let createdID = UUID()

        let result = await makeCoordinator(stateStore: stateStore, counter: counter, createdID: createdID).acquire(
            accountID: 1,
            memberID: 7,
            hasAvailableChatModel: { true }
        )

        XCTAssertEqual(result, .created(threadID: createdID))
        XCTAssertEqual(counter.value, 1)
    }

    func testRequiresAISettingsWhenEmptyAndNoModel() async {
        let stateStore = ChatStateStore()
        let counter = AcquireTestCounter()

        let result = await makeCoordinator(stateStore: stateStore, counter: counter).acquire(
            accountID: 1,
            memberID: 7,
            hasAvailableChatModel: { false }
        )

        XCTAssertEqual(result, .requiresAISettings)
        XCTAssertEqual(counter.value, 0)
    }

    func testDoesNotCheckModelWhenReusableThreadExists() async {
        let stateStore = ChatStateStore()
        let item = makeItem(memberID: 7, latestMessageAt: Date().addingTimeInterval(-301), hasUserMessage: false)
        stateStore.setThreads([item])
        let counter = AcquireTestCounter()
        let modelChecks = AcquireTestCounter()

        let result = await makeCoordinator(stateStore: stateStore, counter: counter).acquire(
            accountID: 1,
            memberID: 7,
            hasAvailableChatModel: {
                modelChecks.value += 1
                return false
            }
        )

        XCTAssertEqual(result, .reuse(threadID: item.id, reason: .latestUnstarted))
        XCTAssertEqual(modelChecks.value, 0)
        XCTAssertEqual(counter.value, 0)
    }

    func testConcurrentRequestsCreateSingleThread() async {
        let stateStore = ChatStateStore()
        let counter = AcquireTestCounter()
        let createdID = UUID()
        let coordinator = makeCoordinator(stateStore: stateStore, counter: counter, createdID: createdID)

        let results = await withTaskGroup(of: ChatThreadAcquisitionResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await coordinator.acquire(accountID: 1, memberID: 7, hasAvailableChatModel: { true })
                }
            }
            var collected: [ChatThreadAcquisitionResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(results.filter { $0 == .created(threadID: createdID) }.count, 1)
        XCTAssertEqual(
            results.filter { $0 == .reuse(threadID: createdID, reason: .joinedCreation) }.count,
            9
        )
    }

    func testMemberScopedConcurrentRequestsDoNotShareThread() async {
        let stateStore = ChatStateStore()
        let counter = AcquireTestCounter()
        let coordinator = ChatThreadAcquisitionCoordinator(
            stateStore: stateStore,
            createThread: { _ in
                counter.value += 1
                return UUID()
            }
        )

        let first = await coordinator.acquire(accountID: 1, memberID: 7, hasAvailableChatModel: { true })
        let second = await coordinator.acquire(accountID: 1, memberID: 8, hasAvailableChatModel: { true })

        XCTAssertEqual(counter.value, 2)
        guard case .created(let firstID) = first, case .created(let secondID) = second else {
            return XCTFail("预期两次独立创建")
        }
        XCTAssertNotEqual(firstID, secondID)
    }

    func testSecondAcquireReusesThreadCreatedByFirst() async {
        let stateStore = ChatStateStore()
        let counter = AcquireTestCounter()
        let createdID = UUID()
        let coordinator = ChatThreadAcquisitionCoordinator(
            stateStore: stateStore,
            createThread: { memberID in
                counter.value += 1
                let thread = ChatThread(id: createdID, memberID: memberID, title: "新建")
                stateStore.setThreads([
                    ChatThreadListItem(
                        id: createdID,
                        thread: thread,
                        latestMessagePreview: "",
                        latestMessageAt: Date(),
                        unreadCount: 0,
                        latestListImageAttachment: nil,
                        hasUserMessage: false
                    )
                ])
                return createdID
            }
        )

        let first = await coordinator.acquire(accountID: 1, memberID: 7, hasAvailableChatModel: { true })
        let second = await coordinator.acquire(accountID: 1, memberID: 7, hasAvailableChatModel: { true })

        XCTAssertEqual(first, .created(threadID: createdID))
        XCTAssertEqual(second, .reuse(threadID: createdID, reason: .latestUnstarted))
        XCTAssertEqual(counter.value, 1)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        stateStore: ChatStateStore,
        counter: AcquireTestCounter,
        createdID: UUID = UUID()
    ) -> ChatThreadAcquisitionCoordinator {
        ChatThreadAcquisitionCoordinator(
            stateStore: stateStore,
            createThread: { _ in
                counter.value += 1
                return createdID
            }
        )
    }

    private func makeItem(
        id: UUID = UUID(),
        memberID: Int?,
        latestMessageAt: Date,
        hasUserMessage: Bool
    ) -> ChatThreadListItem {
        let thread = ChatThread(id: id, memberID: memberID, title: "测试会话")
        return ChatThreadListItem(
            id: id,
            thread: thread,
            latestMessagePreview: "",
            latestMessageAt: latestMessageAt,
            unreadCount: 0,
            latestListImageAttachment: nil,
            hasUserMessage: hasUserMessage
        )
    }
}

/// 测试用计数盒：全部访问发生在 MainActor，避免并发可变捕获。
@MainActor
private final class AcquireTestCounter {
    var value = 0
}
#endif
