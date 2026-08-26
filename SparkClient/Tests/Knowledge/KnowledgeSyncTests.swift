#if canImport(XCTest)
import Foundation
import XCTest

final class KnowledgeSyncTests: XCTestCase {

    // MARK: - KnowledgeOutboxPayload 编解码往返

    func testOutboxPayloadRoundTripsThroughEncodedData() {
        let base = UUID()
        let payload = KnowledgeOutboxPayload(
            knowledgeBaseID: base,
            title: "检查报告解读",
            content: "血脂血糖摘要",
            excerpt: "摘要",
            scope: .personal,
            boundModelID: "agent-1",
            source: .user,
            clientCreatedAt: Date(timeIntervalSince1970: 1_000),
            clientUpdatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let decoded = KnowledgeOutboxPayload.decode(payload.encoded())
        XCTAssertEqual(decoded, payload)
    }

    func testOutboxPayloadDecodeFallsBackToEmptyOnGarbageData() {
        let decoded = KnowledgeOutboxPayload.decode(Data([0xFF, 0x00, 0x11]))
        XCTAssertEqual(decoded, KnowledgeOutboxPayload.empty)
    }

    // MARK: - KnowledgeSyncDTOMapper

    func testMutationRequestOmitsDocumentBodyForDeleteAndRestore() {
        let record = KnowledgeOutboxRecord(
            mutationID: UUID(),
            documentID: UUID(),
            operation: .delete,
            baseRevision: 3,
            payload: KnowledgeOutboxPayload.empty.encoded(),
            requestHash: "",
            attemptCount: 0,
            nextAttemptAt: nil
        )
        let request = KnowledgeSyncDTOMapper.mutationRequest(
            record: record,
            payload: .empty,
            clientPlatform: "ios",
            clientVersion: "1.0",
            deviceID: "device-a"
        )
        XCTAssertNil(request.document)
        XCTAssertEqual(request.operation, "delete")
        XCTAssertEqual(request.baseRevision, 3)
    }

    func testMutationRequestOmitsBaseRevisionForCreate() {
        let record = KnowledgeOutboxRecord(
            mutationID: UUID(),
            documentID: UUID(),
            operation: .create,
            baseRevision: 0,
            payload: Data(),
            requestHash: "",
            attemptCount: 0,
            nextAttemptAt: nil
        )
        let payload = KnowledgeOutboxPayload(title: "t", content: "c", excerpt: "e", scope: .personal, source: .user)
        let request = KnowledgeSyncDTOMapper.mutationRequest(
            record: record,
            payload: payload,
            clientPlatform: "ios",
            clientVersion: "1.0",
            deviceID: nil
        )
        XCTAssertNotNil(request.document)
        XCTAssertNil(request.baseRevision)
        XCTAssertEqual(request.document?.title, "t")
    }

    func testRemoteSnapshotMapsUnknownEnumRawValuesToSafeDefaults() {
        let dto = KnowledgeRemoteDocumentDTO(
            id: UUID(),
            knowledgeBaseId: UUID(),
            title: "t",
            content: "c",
            excerpt: "e",
            scope: "not_a_real_scope",
            boundModelId: nil,
            source: "not_a_real_source",
            revision: 5,
            contentHash: "hash",
            isDeleted: false,
            deletedAt: nil,
            createdAt: nil,
            serverUpdatedAt: Date()
        )
        let snapshot = KnowledgeSyncDTOMapper.remoteSnapshot(from: dto)
        XCTAssertEqual(snapshot.scope, .personal)
        XCTAssertEqual(snapshot.source, .user)
        XCTAssertEqual(snapshot.revision, 5)
    }

    // MARK: - KnowledgeMergePolicy：服务端优先，跳过存在未终态 Outbox 的文档

    func testMergePolicySkipsSnapshotsWithActiveOutbox() {
        let policy = KnowledgeMergePolicy()
        let keepID = UUID()
        let skipID = UUID()
        let snapshots = [
            makeSnapshot(id: keepID),
            makeSnapshot(id: skipID),
        ]
        let applicable = policy.snapshotsToApply(snapshots, activeOutboxDocumentIDs: [skipID])
        XCTAssertEqual(applicable.map(\.id), [keepID])
    }

    func testMergePolicyAppliesAllWhenNoActiveOutbox() {
        let policy = KnowledgeMergePolicy()
        let snapshots = [makeSnapshot(id: UUID()), makeSnapshot(id: UUID())]
        let applicable = policy.snapshotsToApply(snapshots, activeOutboxDocumentIDs: [])
        XCTAssertEqual(applicable.count, 2)
    }

    func testMergePolicyAlwaysPrefersServerSnapshotOnConflict() {
        XCTAssertTrue(KnowledgeMergePolicy().shouldApplyServerSnapshotOnConflict())
    }

    // MARK: - KnowledgeRetryPolicy：退避区间与抖动范围

    func testRetryPolicyDelayStaysWithinExpectedJitterRange() {
        for attempt: Int32 in 0...4 {
            let delay = KnowledgeRetryPolicy.nextAttemptDelay(attemptCount: attempt)
            let base: TimeInterval = [1, 2, 4, 8, 16][Int(attempt)]
            XCTAssertGreaterThanOrEqual(delay, base)
            XCTAssertLessThanOrEqual(delay, base * 1.3)
        }
    }

    func testRetryPolicyClampsOutOfRangeAttemptCounts() {
        let delay = KnowledgeRetryPolicy.nextAttemptDelay(attemptCount: 99)
        XCTAssertGreaterThanOrEqual(delay, 16)
        XCTAssertLessThanOrEqual(delay, 16 * 1.3)
    }

    // MARK: - KnowledgeContentHasher：确定性 + 敏感于输入差异

    func testContentHasherIsDeterministicForSameInput() {
        let a = KnowledgeContentHasher.hash(title: "t", content: "c", scope: .personal, boundModelID: nil)
        let b = KnowledgeContentHasher.hash(title: "t", content: "c", scope: .personal, boundModelID: nil)
        XCTAssertEqual(a, b)
    }

    func testContentHasherChangesWhenContentDiffers() {
        let a = KnowledgeContentHasher.hash(title: "t", content: "c1", scope: .personal, boundModelID: nil)
        let b = KnowledgeContentHasher.hash(title: "t", content: "c2", scope: .personal, boundModelID: nil)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Helpers

    private func makeSnapshot(id: UUID) -> KnowledgeRemoteDocumentSnapshot {
        KnowledgeRemoteDocumentSnapshot(
            id: id,
            knowledgeBaseID: nil,
            title: "t",
            content: "c",
            excerpt: "e",
            scope: .personal,
            boundModelID: nil,
            source: .user,
            revision: 1,
            contentHash: "hash",
            isDeleted: false,
            deletedAt: nil,
            serverUpdatedAt: Date()
        )
    }
}
#endif
