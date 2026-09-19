#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

final class RecentActiveChatThreadSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testSelectionReusesRecentActiveThread() {
        let item = makeItem(memberID: 7, latestMessageAt: now.addingTimeInterval(-300), hasUserMessage: true)

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [item], within: 5 * 60, memberID: 7, now: now),
            .reuse(threadID: item.id, reason: .recentActive)
        )
    }

    func testSelectionReusesLatestUnstartedBeyondFiveMinutes() {
        let item = makeItem(memberID: 7, latestMessageAt: now.addingTimeInterval(-301), hasUserMessage: false)

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [item], within: 5 * 60, memberID: 7, now: now),
            .reuse(threadID: item.id, reason: .latestUnstarted)
        )
    }

    func testSelectionReusesUnstartedAfterOneDay() {
        let item = makeItem(memberID: 7, latestMessageAt: now.addingTimeInterval(-86_400), hasUserMessage: false)

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [item], within: 5 * 60, memberID: 7, now: now),
            .reuse(threadID: item.id, reason: .latestUnstarted)
        )
    }

    func testSelectionPrefersRecentActiveOverLatestUnstarted() {
        let unstarted = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: false
        )
        let active = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-10),
            hasUserMessage: true
        )

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [unstarted, active], within: 5 * 60, memberID: 7, now: now),
            .reuse(threadID: active.id, reason: .recentActive)
        )
    }

    func testSelectionSkipsEarlierEmptyThreadWhenLatestHasUserMessage() {
        let earlierEmpty = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-1000),
            hasUserMessage: false
        )
        let latestStarted = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: true
        )

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [earlierEmpty, latestStarted], within: 5 * 60, memberID: 7, now: now),
            .noReusableThread
        )
    }

    func testSelectionBreaksMessageTimeTieUsingUUIDStableOrder() {
        let first = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: false
        )
        let second = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: false
        )

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [second, first], within: 5 * 60, memberID: 7, now: now),
            .reuse(threadID: first.id, reason: .latestUnstarted)
        )
    }

    func testSelectionKeepsMemberIsolation() {
        let memberA = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: false
        )

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [memberA], within: 5 * 60, memberID: 8, now: now),
            .noReusableThread
        )
    }

    func testSelectionExcludesDeletedNonChatAndUnboundFromLatestUnstarted() {
        let unbound = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            memberID: nil,
            latestMessageAt: now.addingTimeInterval(-301),
            hasUserMessage: false
        )
        let deleted = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            isDeleted: true,
            hasUserMessage: false
        )
        let nonChat = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            memberID: 7,
            latestMessageAt: now.addingTimeInterval(-301),
            scenario: .embedding,
            hasUserMessage: false
        )

        XCTAssertEqual(
            RecentActiveChatThreadSelector.selection(in: [unbound, deleted, nonChat], within: 5 * 60, memberID: 7, now: now),
            .noReusableThread
        )
    }

    private func makeItem(
        id: UUID = UUID(),
        memberID: Int?,
        latestMessageAt: Date,
        isDeleted: Bool = false,
        scenario: AIScenario = .chat,
        hasUserMessage: Bool = false
    ) -> ChatThreadListItem {
        let thread = ChatThread(
            id: id,
            memberID: memberID,
            title: "测试会话",
            scenario: scenario,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? latestMessageAt : nil,
            createdAt: latestMessageAt,
            updatedAt: latestMessageAt
        )
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
#endif
