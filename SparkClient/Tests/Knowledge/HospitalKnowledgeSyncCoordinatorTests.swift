#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000055：知识同步 Coordinator——首次全量、增量、cursor 失效重全量、
/// 部分失败不清绑定、Manifest 移除/下架的引用计数解绑与物理清理。
final class HospitalKnowledgeSyncCoordinatorTests: XCTestCase {
    private let accountID: Int64 = 42
    private let agentID = UUID()
    private let hospitalID = UUID()

    // MARK: - Fixtures

    private func makeItem(
        _ kbID: UUID,
        revision: Int64 = 1,
        indexedRevision: Int64? = nil,
        isDeleted: Bool = false
    ) -> HospitalKnowledgeManifestItem {
        HospitalKnowledgeManifestItem(
            knowledgeBaseID: kbID,
            name: "KB",
            revision: revision,
            vectorStatus: .current,
            indexedRevision: indexedRevision,
            updatedAt: nil,
            isDeleted: isDeleted
        )
    }

    private func makeManifest(
        revision: Int64,
        items: [HospitalKnowledgeManifestItem]
    ) -> HospitalAgentKnowledgeManifest {
        HospitalAgentKnowledgeManifest(
            manifestRevision: revision,
            generatedAt: nil,
            agentID: agentID,
            hospitalID: hospitalID,
            items: items
        )
    }

    private func makeDocument(
        id: UUID = UUID(),
        revision: Int64 = 1,
        isDeleted: Bool = false
    ) -> HospitalKnowledgeDocumentDTO {
        HospitalKnowledgeDocumentDTO(
            id: id,
            title: "标题-\(id.uuidString.prefix(4))",
            content: "正文",
            excerpt: "摘要",
            revision: revision,
            isDeleted: isDeleted,
            updatedAt: nil,
            chunks: []
        )
    }

    private func makePage(
        kbID: UUID,
        documents: [HospitalKnowledgeDocumentDTO],
        cursor: String? = nil,
        hasMore: Bool = false
    ) -> HospitalKnowledgePullPageDTO {
        HospitalKnowledgePullPageDTO(
            knowledgeBaseId: kbID,
            revision: 1,
            vectorStatus: "current",
            indexedRevision: nil,
            cursor: cursor,
            hasMore: hasMore,
            documents: documents
        )
    }

    private func makeCoordinator(
        remote: StubHospitalCareRemoteAPI,
        repository: HospitalKnowledgeInMemoryRepository
    ) -> HospitalKnowledgeSyncCoordinator {
        HospitalKnowledgeSyncCoordinator(
            remoteAPI: remote,
            repository: repository
        )
    }

    /// 自定义描述文本的错误，用于模拟服务端 cursor 失效业务码。
    private struct DescribedError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - 首次全量同步 + 引用计数登记 + tombstone

    func testReconcileFullSyncRegistersBindingAndDropsTombstones() async {
        let kbID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        let kept = makeDocument()
        remote.pullPages = [
            .success(makePage(kbID: kbID, documents: [kept, makeDocument(isDeleted: true)]))
        ]
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kbID)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        let scope = HospitalKnowledgeScope(knowledgeBaseID: kbID)
        let documents = repository.documents(in: scope, accountID: accountID)
        XCTAssertEqual(documents.map(\.documentID), [kept.id])
        let state = repository.syncState(for: scope, accountID: accountID)
        XCTAssertEqual(state?.hasCompletedInitialFullSync, true)
        XCTAssertEqual(state?.boundAgentIDs, [agentID])
        XCTAssertEqual(state?.lastSyncResult, .success)
    }

    // MARK: - Manifest 移除 scope：引用计数解绑，归零后物理清理

    func testReconcileUnbindsScopeRemovedFromManifestAndPurgesWhenUnreferenced() async {
        let kb1 = UUID()
        let kb2 = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.pullPages = [
            .success(makePage(kbID: kb1, documents: [makeDocument()])),
            .success(makePage(kbID: kb2, documents: [makeDocument()]))
        ]
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kb1), makeItem(kb2)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )
        XCTAssertEqual(repository.knownScopes(accountID: accountID).count, 2)

        // 第二轮 Manifest 只剩 kb1；kb2 失去最后一个绑定 → 物理清理。
        await coordinator.reconcileWithManifest(
            makeManifest(revision: 2, items: [makeItem(kb1)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        let remaining = repository.knownScopes(accountID: accountID)
        XCTAssertEqual(remaining, [HospitalKnowledgeScope(knowledgeBaseID: kb1).storageKey])
        XCTAssertNil(repository.syncState(for: HospitalKnowledgeScope(knowledgeBaseID: kb2), accountID: accountID))
    }

    // MARK: - 部分同步失败：既有绑定不清除、不推进解绑

    func testReconcilePartialFailureKeepsExistingBindings() async {
        let kb1 = UUID()
        let kb2 = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.pullPages = [.success(makePage(kbID: kb1, documents: [makeDocument()]))]
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kb1)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        // 第二轮：kb1 增量成功（空页），kb2 全量失败 → 不登记新绑定、不做解绑推进。
        remote.pullPages = [
            .success(makePage(kbID: kb1, documents: [])),
            .failure(StubHospitalCareRemoteAPI.StubError.network)
        ]
        await coordinator.reconcileWithManifest(
            makeManifest(revision: 2, items: [makeItem(kb1), makeItem(kb2)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        let state1 = repository.syncState(for: HospitalKnowledgeScope(knowledgeBaseID: kb1), accountID: accountID)
        XCTAssertEqual(state1?.boundAgentIDs, [agentID])
        XCTAssertEqual(state1?.lastSyncResult, .success)
        let state2 = repository.syncState(for: HospitalKnowledgeScope(knowledgeBaseID: kb2), accountID: accountID)
        XCTAssertEqual(state2?.lastSyncResult, .failed)
        XCTAssertNil(state2?.boundAgentIDs)
    }

    // MARK: - 下架/禁同步：不发请求、不动本地数据

    func testReconcileSkipsNetworkWhenSyncDisabled() async {
        let kbID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)
        let capabilities = HospitalConversationCapabilities(
            canReadCachedHistory: true,
            canPullRemoteMessages: true,
            canSendMessage: false,
            canSyncKnowledge: false,
            readOnlyReason: "agent_unpublished"
        )

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kbID)]),
            agentID: agentID,
            capabilities: capabilities,
            accountID: accountID
        )

        XCTAssertEqual(remote.pullCallCount, 0)
        XCTAssertTrue(repository.knownScopes(accountID: accountID).isEmpty)
    }

    // MARK: - Manifest 缺失：解绑该智能体全部 scope；共享 scope 只减计数

    func testReconcileNilManifestUnbindsOnlyThatAgent() async {
        let kbID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.pullPages = [.success(makePage(kbID: kbID, documents: [makeDocument()]))]
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kbID)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        // 另一智能体也绑定同一 scope（共享）。
        let otherAgent = UUID()
        let scope = HospitalKnowledgeScope(knowledgeBaseID: kbID)
        if var state = repository.syncState(for: scope, accountID: accountID) {
            state.boundAgentIDs = [agentID, otherAgent]
            repository.updateSyncState(state, accountID: accountID)
        }

        // 本智能体 Manifest 缺失 → 只移除本智能体的绑定，scope 保留。
        await coordinator.reconcileWithManifest(
            nil,
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )
        XCTAssertEqual(
            repository.syncState(for: scope, accountID: accountID)?.boundAgentIDs,
            [otherAgent]
        )
        XCTAssertEqual(repository.documents(in: scope, accountID: accountID).count, 1)

        // 最后一个绑定者退出 → 物理清理。
        await coordinator.reconcileWithManifest(
            nil,
            agentID: otherAgent,
            capabilities: .optimisticDefault,
            accountID: accountID
        )
        XCTAssertTrue(repository.knownScopes(accountID: accountID).isEmpty)
    }

    // MARK: - cursor 失效：物理清理后全量重拉

    func testCursorInvalidFallsBackToFullResync() async {
        let kbID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        let initial = makeDocument()
        remote.pullPages = [
            .success(makePage(kbID: kbID, documents: [initial], cursor: "cursor-1"))
        ]
        let repository = HospitalKnowledgeInMemoryRepository()
        let coordinator = makeCoordinator(remote: remote, repository: repository)

        await coordinator.reconcileWithManifest(
            makeManifest(revision: 1, items: [makeItem(kbID)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )
        XCTAssertEqual(
            repository.syncState(for: HospitalKnowledgeScope(knowledgeBaseID: kbID), accountID: accountID)?.cursor,
            "cursor-1"
        )

        // manifestRevision 变化 → 走增量；服务端判定 cursor 失效 → 全量重拉。
        let refreshed = makeDocument()
        remote.pullPages = [
            .failure(DescribedError(description: "HOSPITAL_KNOWLEDGE_CURSOR_INVALID")),
            .success(makePage(kbID: kbID, documents: [refreshed]))
        ]
        await coordinator.reconcileWithManifest(
            makeManifest(revision: 2, items: [makeItem(kbID)]),
            agentID: agentID,
            capabilities: .optimisticDefault,
            accountID: accountID
        )

        // 调用序列：首次全量(nil) → 增量(cursor-1) 失效 → 重全量(nil)。
        XCTAssertEqual(remote.pullCursors.count, 3)
        XCTAssertEqual(remote.pullCursors[1], "cursor-1")
        XCTAssertNil(remote.pullCursors[2])
        let documents = repository.documents(in: HospitalKnowledgeScope(knowledgeBaseID: kbID), accountID: accountID)
        XCTAssertEqual(documents.map(\.documentID), [refreshed.id])
    }

    // MARK: - 门禁映射（Q27/Q28）

    func testMapCapabilitiesDefaultsToOptimisticWhenDTO缺失() {
        let capabilities = FetchHospitalConversationContextUseCase.mapCapabilities(nil)
        XCTAssertEqual(capabilities, .optimisticDefault)
        XCTAssertTrue(capabilities.canSendMessage)
    }

    func testMapCapabilitiesPropagatesUnpublishedGate() {
        let dto = HospitalConversationCapabilitiesDTO(
            canReadCachedHistory: true,
            canPullRemoteMessages: true,
            canSendMessage: false,
            canSyncKnowledge: false,
            readOnlyReason: "agent_unpublished"
        )
        let capabilities = FetchHospitalConversationContextUseCase.mapCapabilities(dto)
        XCTAssertFalse(capabilities.canSendMessage)
        XCTAssertFalse(capabilities.canSyncKnowledge)
        XCTAssertEqual(capabilities.readOnlyReason, "agent_unpublished")
    }

    func testMemberAccessRevokedCapabilitiesAreReadOnly() {
        let capabilities = HospitalConversationCapabilities.memberAccessRevoked
        XCTAssertTrue(capabilities.canReadCachedHistory)
        XCTAssertFalse(capabilities.canPullRemoteMessages)
        XCTAssertFalse(capabilities.canSendMessage)
        XCTAssertFalse(capabilities.canSyncKnowledge)
        XCTAssertEqual(capabilities.readOnlyReason, "member_access_revoked")
    }
}
#endif
