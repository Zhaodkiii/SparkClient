#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000057：统一消息列表纯逻辑（筛选/搜索/排序/未读聚合/角标文案）。
final class UnifiedConversationListLogicTests: XCTestCase {

    // MARK: - D-017：类型筛选（unknown 只在「全部」可见）

    func testTypeFilterHidesUnknownFromSpecificFilters() {
        let unknown = makeUnifiedItem(kind: .unknown, classificationState: .resolving)
        let ai = makeUnifiedItem(kind: .ordinaryAI)
        let hospital = makeUnifiedItem(kind: .hospitalAgent)
        let items = [unknown, ai, hospital]

        XCTAssertEqual(items.visibleItems(filter: .all, query: "").count, 3)
        XCTAssertEqual(items.visibleItems(filter: .ordinaryAI, query: "").map(\.threadID), [ai.threadID])
        XCTAssertEqual(items.visibleItems(filter: .hospitalAgent, query: "").map(\.threadID), [hospital.threadID])
        XCTAssertTrue(items.visibleItems(filter: .telemedicine, query: "").isEmpty)
    }

    // MARK: - D-013：搜索只命中标题/身份 token

    func testSearchMatchesOnlyIdentityAndTitleTokens() {
        let match = makeUnifiedItem(primaryTitle: "心脏康复咨询", searchTokens: ["心脏康复咨询"])
        let previewOnly = makeUnifiedItem(primaryTitle: "其他", searchTokens: ["其他"])
        let items = [match, previewOnly]

        let result = items.visibleItems(filter: .all, query: " 心脏 ")
        XCTAssertEqual(result.map(\.threadID), [match.threadID])

        // 空白查询等价于未搜索
        XCTAssertEqual(items.visibleItems(filter: .all, query: "   ").count, 2)
    }

    // MARK: - D-010：置顶区优先 + 区内最近消息倒序 + threadID 稳定兜底

    func testSortingPinnedFirstThenLatestMessageDesc() {
        let now = Date()
        let old = makeUnifiedItem(latestMessageAt: now.addingTimeInterval(-3600))
        let recent = makeUnifiedItem(latestMessageAt: now)
        let pinnedOld = makeUnifiedItem(isPinned: true, latestMessageAt: now.addingTimeInterval(-7200))
        let items = [old, pinnedOld, recent]

        let sorted = items.visibleItems(filter: .all, query: "")
        XCTAssertEqual(sorted.map(\.threadID), [pinnedOld.threadID, recent.threadID, old.threadID])
    }

    func testSortingSameTimestampFallsBackToThreadIDAscending() {
        let now = Date()
        let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let items = [makeUnifiedItem(threadID: idB, latestMessageAt: now),
                     makeUnifiedItem(threadID: idA, latestMessageAt: now)]

        let sorted = items.visibleItems(filter: .all, query: "")
        XCTAssertEqual(sorted.map(\.threadID), [idA, idB])
    }

    // MARK: - D-015：未读聚合含 unknown，负数保护

    func testAggregatedUnreadIncludesUnknownAndClampsNegatives() {
        let items = [
            makeUnifiedItem(kind: .ordinaryAI, unreadCount: 3),
            makeUnifiedItem(kind: .hospitalAgent, unreadCount: 2),
            makeUnifiedItem(kind: .unknown, classificationState: .retryableFailure, unreadCount: 4),
            makeUnifiedItem(unreadCount: -5),
        ]
        XCTAssertEqual(items.aggregatedUnreadCount, 9)
    }

    // MARK: - D-015/25.4：分段角标文案

    func testUnreadBadgeText() {
        XCTAssertNil(unifiedUnreadBadgeText(0))
        XCTAssertNil(unifiedUnreadBadgeText(-1))
        XCTAssertEqual(unifiedUnreadBadgeText(1), "1")
        XCTAssertEqual(unifiedUnreadBadgeText(99), "99")
        XCTAssertEqual(unifiedUnreadBadgeText(100), "99+")
        XCTAssertEqual(unifiedUnreadBadgeText(10_000), "99+")
    }

    // MARK: - Fixture

    private func makeUnifiedItem(
        threadID: UUID = UUID(),
        kind: ConversationKind = .ordinaryAI,
        classificationState: ConversationClassificationState = .resolved,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        latestMessageAt: Date = Date(),
        primaryTitle: String = "会话",
        searchTokens: [String]? = nil
    ) -> UnifiedConversationListItem {
        UnifiedConversationListItem(
            threadID: threadID,
            memberID: nil,
            conversationKind: kind,
            classificationState: classificationState,
            serviceStatus: nil,
            capability: kind == .unknown ? .unknownReadOnly : .ordinaryAI,
            primaryTitle: primaryTitle,
            secondaryIdentity: nil,
            threadTitle: nil,
            typeBadge: kind == .unknown ? .confirming : .ordinaryAI,
            avatar: .threadAppearance(iconName: nil, iconColorName: nil),
            latestMessagePreview: "",
            latestMessageAt: latestMessageAt,
            unreadCount: unreadCount,
            isPinned: isPinned,
            memberDisplayName: nil,
            searchTokens: searchTokens ?? [primaryTitle.lowercased()],
            route: .ordinaryAI(threadID: threadID, memberID: nil),
            thread: ChatThread(id: threadID, title: primaryTitle),
            bindingRevision: nil
        )
    }
}

/// CHAT-000057 D-021：服务状态受控映射（未知值不猜测，映射为 unsupported）。
final class ConversationServiceStatusMappingTests: XCTestCase {
    func testKnownRawValuesMapToControlledCases() {
        XCTAssertEqual(ConversationServiceStatus(rawValue: "active"), .active)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "doctor_taken_over"), .doctorTakenOver)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "doctor_joined"), .doctorJoined)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "ended"), .ended)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "suspended"), .suspended)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "agent_offline"), .agentUnavailable)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "hospital_service_unavailable"), .hospitalUnavailable)
        XCTAssertEqual(ConversationServiceStatus(rawValue: "consultation_completed"), .consultationCompleted)
    }

    func testDoctorJoinedHasTakeoverSemantics() {
        // 服务端 context 接口实际下发值：医生已接管 → 可发送、AI 不回复（38.6）。
        let status = ConversationServiceStatus.doctorJoined
        XCTAssertTrue(status.allowsSending)
        XCTAssertTrue(status.isDoctorTakeover)
        XCTAssertTrue(ConversationServiceStatus.doctorTakenOver.isDoctorTakeover)
        XCTAssertFalse(ConversationServiceStatus.active.isDoctorTakeover)
        XCTAssertEqual(status.localizedBadge, ConversationServiceStatus.doctorTakenOver.localizedBadge)
        XCTAssertNil(status.localizedReadOnlyReason)
    }

    func testUnrecognizedRawValueMapsToUnsupportedPreservingRaw() {
        let status = ConversationServiceStatus(rawValue: "future_status_x")
        XCTAssertEqual(status, .unsupported("future_status_x"))
        XCTAssertEqual(status.rawValue, "future_status_x")
        XCTAssertFalse(status.allowsSending)
    }

    func testAllowsSendingOnlyForActiveAndDoctorTakenOver() {
        XCTAssertTrue(ConversationServiceStatus.active.allowsSending)
        XCTAssertTrue(ConversationServiceStatus.doctorTakenOver.allowsSending)
        XCTAssertFalse(ConversationServiceStatus.ended.allowsSending)
        XCTAssertFalse(ConversationServiceStatus.suspended.allowsSending)
        XCTAssertFalse(ConversationServiceStatus.agentUnavailable.allowsSending)
    }

    func testCodableRoundTripPreservesUnsupportedRaw() throws {
        let original = ConversationServiceStatus.unsupported("brand_new_state")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversationServiceStatus.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

/// CHAT-000057 D-016/26.6：统一已读确认入口。
final class MarkConversationReadUseCaseTests: XCTestCase {
    func testUnknownCapabilitySkipsWithoutTouchingRepository() async {
        let store = StubChatMessageStoring()
        let useCase = MarkConversationReadUseCase(repository: store, logger: NullLogger())

        let outcome = await useCase.execute(
            threadID: UUID(),
            accountID: 7,
            capability: .unknownReadOnly
        )

        XCTAssertEqual(outcome, .skippedUnconfirmed)
        XCTAssertTrue(store.markedCalls.isEmpty)
    }

    func testRevokedCapabilitySkipsWithoutTouchingRepository() async {
        let store = StubChatMessageStoring()
        let useCase = MarkConversationReadUseCase(repository: store, logger: NullLogger())

        let outcome = await useCase.execute(
            threadID: UUID(),
            accountID: 7,
            capability: .revoked
        )

        XCTAssertEqual(outcome, .skippedRevoked)
        XCTAssertTrue(store.markedCalls.isEmpty)
    }

    func testOrdinaryCapabilityMarksWithinBoundary() async {
        let store = StubChatMessageStoring()
        store.markedResult = 5
        let useCase = MarkConversationReadUseCase(repository: store, logger: NullLogger())
        let threadID = UUID()
        let boundary = Date()

        let outcome = await useCase.execute(
            threadID: threadID,
            accountID: 7,
            capability: .ordinaryAI,
            readBoundary: boundary
        )

        XCTAssertEqual(outcome, .marked(markedCount: 5))
        XCTAssertEqual(store.markedCalls.count, 1)
        XCTAssertEqual(store.markedCalls.first?.threadID, threadID)
        XCTAssertEqual(store.markedCalls.first?.boundary, boundary)
    }

    func testRepeatedMarkIsIdempotentAtRepositoryLevel() async {
        let store = StubChatMessageStoring()
        store.markedResult = 0 // 第二次无可清零消息（幂等命中）
        let useCase = MarkConversationReadUseCase(repository: store, logger: NullLogger())

        let outcome = await useCase.execute(
            threadID: UUID(),
            accountID: 7,
            capability: .hospitalAgentTakenOver
        )

        XCTAssertEqual(outcome, .marked(markedCount: 0))
    }
}

/// 仅实现 markAssistantMessagesRead 的存储替身；其余接口返回空事实，不参与本用例断言。
private final class StubChatMessageStoring: ChatMessageStoring, @unchecked Sendable {
    var markedCalls: [(threadID: UUID, boundary: Date)] = []
    var markedResult = 0

    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage] { [] }
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] { [] }
    func loadUsageSummary(clientMessageID: UUID) async -> ChatMessageUsageSummary? { nil }
    func countMessages(threadID: UUID) async -> Int { 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async {}
    func markAssistantMessagesRead(threadID: UUID, upTo boundary: Date) async -> Int {
        markedCalls.append((threadID, boundary))
        return markedResult
    }
    func applyPushMessageAck(
        clientMessageID: UUID,
        serverMessageID: String?,
        serverUpdatedAt: Date,
        notifyUI: Bool
    ) async {}
    func updateMessageBlocks(clientMessageID: UUID, blocks: [ChatMessageBlock], markPendingForSync: Bool) async {}
    func upsertMessageBlock(clientMessageID: UUID, block: ChatMessageBlock, markPendingForSync: Bool) async -> Bool { false }
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async {}
    func loadOutboxMessages(limit: Int) async -> [ChatMessage] { [] }
    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock] { [] }
    func markMessageBlocksSynced(ids: [UUID]) async {}
    func appendUsageEvent(_ event: ChatMessageUsageEvent) async {}
    func upsertUsageSummary(_ summary: ChatMessageUsageSummary) async {}
}
#endif
