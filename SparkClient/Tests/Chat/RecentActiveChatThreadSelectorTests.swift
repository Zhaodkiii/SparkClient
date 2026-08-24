#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

final class RecentActiveChatThreadSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testIncludesThreadAtFiveMinuteBoundary() {
        let item = makeItem(memberID: 7, latestMessageAt: now.addingTimeInterval(-300))

        XCTAssertEqual(
            RecentActiveChatThreadSelector.mostRecentActiveThreadID(
                in: [item],
                within: 5 * 60,
                memberID: 7,
                now: now
            ),
            item.id
        )
    }

    func testExcludesThreadOlderThanFiveMinutes() {
        let item = makeItem(memberID: 7, latestMessageAt: now.addingTimeInterval(-301))

        XCTAssertNil(
            RecentActiveChatThreadSelector.mostRecentActiveThreadID(
                in: [item],
                within: 5 * 60,
                memberID: 7,
                now: now
            )
        )
    }

    func testSelectsNewestMatchingMemberEvenWhenInputIsUnsorted() {
        let older = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, memberID: 7, latestMessageAt: now.addingTimeInterval(-240))
        let newest = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, memberID: 7, latestMessageAt: now.addingTimeInterval(-30))
        let otherMember = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, memberID: 8, latestMessageAt: now.addingTimeInterval(-1))

        XCTAssertEqual(
            RecentActiveChatThreadSelector.mostRecentActiveThreadID(
                in: [older, otherMember, newest],
                within: 5 * 60,
                memberID: 7,
                now: now
            ),
            newest.id
        )
    }

    func testExcludesUnboundDeletedAndNonChatThreads() {
        let unbound = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, memberID: nil, latestMessageAt: now.addingTimeInterval(-1))
        let deleted = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, memberID: 7, latestMessageAt: now.addingTimeInterval(-1), isDeleted: true)
        let nonChat = makeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, memberID: 7, latestMessageAt: now.addingTimeInterval(-1), scenario: .embedding)

        XCTAssertNil(
            RecentActiveChatThreadSelector.mostRecentActiveThreadID(
                in: [unbound, deleted, nonChat],
                within: 5 * 60,
                memberID: 7,
                now: now
            )
        )
    }

    func testNilMemberFilterPreservesChatTabGlobalSelection() {
        let item = makeItem(memberID: 8, latestMessageAt: now.addingTimeInterval(-1))

        XCTAssertEqual(
            RecentActiveChatThreadSelector.mostRecentActiveThreadID(
                in: [item],
                within: 5 * 60,
                now: now
            ),
            item.id
        )
    }

    private func makeItem(
        id: UUID = UUID(),
        memberID: Int?,
        latestMessageAt: Date,
        isDeleted: Bool = false,
        scenario: AIScenario = .chat
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
            latestListImageAttachment: nil
        )
    }
}
#endif
