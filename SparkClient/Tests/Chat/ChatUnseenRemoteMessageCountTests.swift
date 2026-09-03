#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000056 Q6/17.5：`ChatStateStore` per-thread「有新消息」计数生命周期。
@MainActor
final class ChatUnseenRemoteMessageCountStoreTests: XCTestCase {
    func testAccumulatesByRealAppendedCountAcrossBatches() {
        let store = ChatStateStore()
        let threadID = UUID()

        // 同一批远端消息合并后一次性累加（3 条），下一批再累加（2 条），不按 hint 次数
        store.addUnseenRemoteMessageCount(3, for: threadID)
        store.addUnseenRemoteMessageCount(2, for: threadID)

        XCTAssertEqual(store.unseenRemoteMessageCount(for: threadID), 5)
    }

    func testZeroAndNegativeDeltaAreIgnored() {
        let store = ChatStateStore()
        let threadID = UUID()

        store.addUnseenRemoteMessageCount(0, for: threadID)
        store.addUnseenRemoteMessageCount(-1, for: threadID)

        XCTAssertEqual(store.unseenRemoteMessageCount(for: threadID), 0)
    }

    func testClearPerThreadKeepsOtherThreads() {
        let store = ChatStateStore()
        let threadA = UUID()
        let threadB = UUID()
        store.addUnseenRemoteMessageCount(2, for: threadA)
        store.addUnseenRemoteMessageCount(4, for: threadB)

        store.clearUnseenRemoteMessageCount(for: threadA)

        XCTAssertEqual(store.unseenRemoteMessageCount(for: threadA), 0)
        XCTAssertEqual(store.unseenRemoteMessageCount(for: threadB), 4)
    }

    func testClearAllOnMemberSwitch() {
        let store = ChatStateStore()
        store.addUnseenRemoteMessageCount(2, for: UUID())
        store.addUnseenRemoteMessageCount(3, for: UUID())

        store.clearAllUnseenRemoteMessageCounts()

        XCTAssertTrue(store.unseenRemoteMessageCountByThread.isEmpty)
    }

    func testSessionSwitchResetClearsCounts() {
        let store = ChatStateStore()
        let threadID = UUID()
        store.addUnseenRemoteMessageCount(2, for: threadID)

        store.resetForSessionSwitch()

        XCTAssertEqual(store.unseenRemoteMessageCount(for: threadID), 0)
    }
}

/// CHAT-000056 Q6.3：「按真实新增条数累加」依赖 `ConversationUpdateBuilder` 的 appended 计算。
final class ConversationUpdateBuilderUnseenCountTests: XCTestCase {
    private let threadID = UUID()

    func testTailAppendedMessagesProduceStructuralPlanWithAppendedIDs() {
        let base = [makeMessage("m1"), makeMessage("m2")]
        let appended = [makeMessage("m3"), makeMessage("m4")]

        let plan = ConversationUpdateBuilder.plan(previous: base, current: base + appended)

        XCTAssertEqual(plan.kind, .structural)
        XCTAssertEqual(plan.appendedItemIDs.count, 2)
        XCTAssertTrue(plan.prependedItemIDs.isEmpty)
    }

    func testPrependedHistoryIsNotCountedAsNewMessages() {
        let older = [makeMessage("m0")]
        let base = [makeMessage("m1"), makeMessage("m2")]

        let plan = ConversationUpdateBuilder.plan(previous: base, current: older + base)

        XCTAssertEqual(plan.kind, .structural)
        XCTAssertTrue(plan.appendedItemIDs.isEmpty)
        XCTAssertEqual(plan.prependedItemIDs.count, 1)
    }

    func testInPlaceUpdateIsMinorAndProducesNoAppendedIDs() {
        let first = makeMessage("m1", text: "旧")
        let second = makeMessage("m2")

        let plan = ConversationUpdateBuilder.plan(previous: [first, second], current: [first, second])

        XCTAssertEqual(plan.kind, .minor)
        XCTAssertTrue(plan.appendedItemIDs.isEmpty)
    }

    func testEmptyPreviousIsReloadAllAndExcludedFromUnseenCounting() {
        let plan = ConversationUpdateBuilder.plan(previous: [], current: [makeMessage("m1")])

        XCTAssertEqual(plan.kind, .reloadAll)
    }

    private func makeMessage(_ text: String, text body: String? = nil) -> ChatMessage {
        ChatMessage(
            threadID: threadID,
            role: .assistant,
            blocks: [ChatMessageBlock(kind: .text, text: body ?? text)]
        )
    }
}

/// CHAT-000056 Q6.1/Q6.2：贴底自动跟随；阅读历史（未贴底）不抢占滚动位置。
@MainActor
final class ChatSwiftUIScrollAnchorPolicyUnseenTests: XCTestCase {
    private let threadID = UUID()

    func testInteractedUserAtBottomFollowsNewRemoteMessage() {
        let policy = makeInteractedPolicy()
        let next = makeFrame(lastText: "医生新消息")

        let shouldScroll = policy.shouldScrollToBottom(
            frame: next,
            behavior: .stable,
            layoutGeneration: 0,
            isAtBottom: true
        )

        XCTAssertTrue(shouldScroll)
    }

    func testInteractedUserReadingHistoryDoesNotScroll() {
        let policy = makeInteractedPolicy()
        let next = makeFrame(lastText: "医生新消息")

        let shouldScroll = policy.shouldScrollToBottom(
            frame: next,
            behavior: .stable,
            layoutGeneration: 0,
            isAtBottom: false
        )

        XCTAssertFalse(shouldScroll)
    }

    func testNonInteractedUserFollowsNewRemoteMessage() {
        let policy = ChatSwiftUIScrollAnchorPolicy()
        policy.reset(to: makeFrame(lastText: "旧消息"), layoutGeneration: 0, reason: .navigationReturn)
        let next = makeFrame(lastText: "医生新消息")

        let shouldScroll = policy.shouldScrollToBottom(
            frame: next,
            behavior: .stable,
            layoutGeneration: 0,
            isAtBottom: false
        )

        XCTAssertTrue(shouldScroll)
    }

    private func makeInteractedPolicy() -> ChatSwiftUIScrollAnchorPolicy {
        let policy = ChatSwiftUIScrollAnchorPolicy()
        policy.reset(to: makeFrame(lastText: "旧消息"), layoutGeneration: 0, reason: .navigationReturn)
        policy.markUserInteraction()
        return policy
    }

    private func makeFrame(lastText: String) -> ChatSwiftUIConversationFrame {
        let message = ChatMessage(
            threadID: threadID,
            role: .assistant,
            blocks: [ChatMessageBlock(kind: .text, text: lastText)]
        )
        return ChatSwiftUIConversationFrameBuilder.make(
            threadID: threadID,
            visibleMessages: [message],
            hasMoreMessages: false,
            isLoadingMoreMessages: false,
            lockBottomViewport: false,
            scrollToBottomRequestGeneration: 0,
            streamingStates: [:]
        )
    }
}
#endif
