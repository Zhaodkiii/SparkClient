#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000054：医院会话 scope 的持久化、服务端回源恢复、批量回填与普通列表排除。
final class HospitalConversationScopeResolutionTests: XCTestCase {
    private let accountID: Int64 = 42

    private func makeStore() -> HospitalConversationScopeStore {
        let suite = "HospitalConversationScopeResolutionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return HospitalConversationScopeStore(defaults: defaults)
    }

    // MARK: - ScopeStore

    func testScopeStoreRoundTripAndAccountIsolation() {
        let store = makeStore()
        let threadID = UUID()
        let scope = HospitalConversationScope(
            threadID: threadID,
            agentID: UUID(),
            memberID: 7,
            hospitalID: UUID()
        )
        store.remember(scope, accountID: accountID)

        XCTAssertEqual(store.scope(for: threadID, accountID: accountID), scope)
        XCTAssertNil(store.scope(for: threadID, accountID: 999))
        XCTAssertNil(store.scope(for: UUID(), accountID: accountID))
    }

    func testScopeStoreClearAllRemovesEveryAccount() {
        let store = makeStore()
        let first = HospitalConversationScope(threadID: UUID(), agentID: UUID(), memberID: 1, hospitalID: UUID())
        let second = HospitalConversationScope(threadID: UUID(), agentID: UUID(), memberID: 2, hospitalID: UUID())
        store.remember(first, accountID: 1)
        store.remember(second, accountID: 2)

        store.clearAll()

        XCTAssertNil(store.scope(for: first.threadID, accountID: 1))
        XCTAssertNil(store.scope(for: second.threadID, accountID: 2))
    }

    // MARK: - 服务端 context 回源

    func testResolvePrefersLocalScopeWithoutRemoteCall() async throws {
        let store = makeStore()
        let threadID = UUID()
        let scope = HospitalConversationScope(
            threadID: threadID,
            agentID: UUID(),
            memberID: 7,
            hospitalID: UUID()
        )
        store.remember(scope, accountID: accountID)
        let remote = StubHospitalCareRemoteAPI()
        let useCase = ResolveHospitalConversationScopeUseCase(remoteAPI: remote, scopeStore: store)

        let resolved = try await useCase.execute(threadID: threadID, accountID: accountID)

        XCTAssertEqual(resolved, scope)
        XCTAssertEqual(remote.fetchContextCallCount, 0)
    }

    func testResolveRecoversScopeFromServerContext() async throws {
        let store = makeStore()
        let threadID = UUID()
        let context = HospitalCareTestFixtures.contextDTO(threadID: threadID, memberID: 7)
        let remote = StubHospitalCareRemoteAPI()
        remote.contextResult = .success(context)
        let useCase = ResolveHospitalConversationScopeUseCase(remoteAPI: remote, scopeStore: store)

        let resolved = try await useCase.execute(threadID: threadID, accountID: accountID)

        XCTAssertEqual(resolved?.threadID, threadID)
        XCTAssertEqual(resolved?.agentID, context.agent.id)
        XCTAssertEqual(resolved?.memberID, 7)
        // 恢复后写入本地，第二次不再回源。
        let again = try await useCase.execute(threadID: threadID, accountID: accountID)
        XCTAssertEqual(again, resolved)
        XCTAssertEqual(remote.fetchContextCallCount, 1)
    }

    func testResolveReturnsNilForOrdinaryConversation() async throws {
        let store = makeStore()
        let remote = StubHospitalCareRemoteAPI()
        remote.contextResult = .success(nil) // 404 → 普通会话
        let useCase = ResolveHospitalConversationScopeUseCase(remoteAPI: remote, scopeStore: store)

        let resolved = try await useCase.execute(threadID: UUID(), accountID: accountID)

        XCTAssertNil(resolved)
    }

    func testResolveThrowsWhenContextRequestFails() async {
        let store = makeStore()
        let remote = StubHospitalCareRemoteAPI()
        remote.contextResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = ResolveHospitalConversationScopeUseCase(remoteAPI: remote, scopeStore: store)

        do {
            _ = try await useCase.execute(threadID: UUID(), accountID: accountID)
            XCTFail("请求失败必须抛错，不能静默按普通会话处理")
        } catch {
            // 期望抛错
        }
    }

    // MARK: - 批量回填

    func testHydrateWritesAllHospitalScopes() async {
        let store = makeStore()
        let remote = StubHospitalCareRemoteAPI()
        let validA = HospitalCareTestFixtures.conversationDTO(memberID: 7)
        let validB = HospitalCareTestFixtures.conversationDTO(memberID: 8)
        let missingMember = HospitalCareTestFixtures.conversationDTO(memberID: nil)
        let missingHospital = HospitalCareTestFixtures.conversationDTO(memberID: 7, hospitalID: nil)
        remote.allConversationsResult = .success([validA, validB, missingMember, missingHospital])
        let useCase = HydrateHospitalConversationScopesUseCase(remoteAPI: remote, scopeStore: store)

        let count = await useCase.execute(accountID: accountID)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.scope(for: validA.threadId, accountID: accountID)?.agentID, validA.agent.id)
        XCTAssertEqual(store.scope(for: validB.threadId, accountID: accountID)?.memberID, 8)
        XCTAssertNil(store.scope(for: missingMember.threadId, accountID: accountID))
        XCTAssertNil(store.scope(for: missingHospital.threadId, accountID: accountID))
    }

    func testHydrateFailureIsSilent() async {
        let store = makeStore()
        let remote = StubHospitalCareRemoteAPI()
        remote.allConversationsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = HydrateHospitalConversationScopesUseCase(remoteAPI: remote, scopeStore: store)

        let count = await useCase.execute(accountID: accountID)

        XCTAssertEqual(count, 0)
    }

    // MARK: - 普通对话投影排除医院 Thread

    @MainActor
    func testOrdinaryProjectionExcludesHospitalThreads() {
        let store = makeStore()
        let ordinaryID = UUID()
        let hospitalID = UUID()
        store.remember(
            HospitalConversationScope(
                threadID: hospitalID,
                agentID: UUID(),
                memberID: 7,
                hospitalID: UUID()
            ),
            accountID: accountID
        )
        let items = [makeItem(id: ordinaryID), makeItem(id: hospitalID)]

        let projected = ChatListViewModel.excludingHospitalThreads(items) {
            store.scope(for: $0, accountID: accountID) != nil
        }

        XCTAssertEqual(projected.map(\.id), [ordinaryID])
    }

    private func makeItem(id: UUID) -> ChatThreadListItem {
        ChatThreadListItem(
            id: id,
            thread: ChatThread(id: id, memberID: 7, title: "会话"),
            latestMessagePreview: "",
            latestMessageAt: Date(),
            unreadCount: 0,
            latestListImageAttachment: nil,
            hasUserMessage: true
        )
    }
}
#endif
