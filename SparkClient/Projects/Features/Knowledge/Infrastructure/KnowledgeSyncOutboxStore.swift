import Foundation

/// 知识同步 Outbox 读写门面；实际持久化收口在 `CoreDataKnowledgeRepository`，
/// 此处只是 actor 化的调用边界，对齐 Chat 侧 `ChatOutboxStore` 的分层方式。
actor KnowledgeSyncOutboxStore {
    private let repository: any KnowledgeRepository

    init(repository: any KnowledgeRepository) {
        self.repository = repository
    }

    func pending(limit: Int = 50) async -> [KnowledgeOutboxRecord] {
        await repository.loadPendingOutbox(limit: limit)
    }

    func documentIDsWithActiveOutbox() async -> Set<UUID> {
        await repository.documentIDsWithActiveOutbox()
    }

    func markSending(mutationIDs: [UUID]) async {
        await repository.markOutboxSending(mutationIDs: mutationIDs)
    }

    func markAccepted(mutationID: UUID, documentID: UUID, revision: Int64, serverUpdatedAt: Date, contentHash: String) async {
        await repository.markOutboxAcceptedAndApplyServerFields(
            mutationID: mutationID,
            documentID: documentID,
            revision: revision,
            serverUpdatedAt: serverUpdatedAt,
            contentHash: contentHash
        )
    }

    func resolveByServer(mutationID: UUID, snapshot: KnowledgeRemoteDocumentSnapshot) async {
        await repository.resolveConflictWithServerSnapshot(mutationID: mutationID, snapshot: snapshot)
    }

    func markFailedRetryable(mutationID: UUID, errorCode: String, nextAttemptAt: Date) async {
        await repository.markOutboxFailedRetryable(mutationID: mutationID, errorCode: errorCode, nextAttemptAt: nextAttemptAt)
    }

    func markFailedPermanent(mutationID: UUID, errorCode: String) async {
        await repository.markOutboxFailedPermanent(mutationID: mutationID, errorCode: errorCode)
    }
}

/// 退避重试策略：1/2/4/8/16 秒 + 0–30% jitter，单轮最多 5 次（工单 11.5）。
enum KnowledgeRetryPolicy {
    static let maxAttempts = 5
    private static let baseIntervals: [TimeInterval] = [1, 2, 4, 8, 16]

    static func nextAttemptDelay(attemptCount: Int32) -> TimeInterval {
        let index = min(max(Int(attemptCount), 0), baseIntervals.count - 1)
        let base = baseIntervals[index]
        let jitter = base * Double.random(in: 0...0.3)
        return base + jitter
    }
}
