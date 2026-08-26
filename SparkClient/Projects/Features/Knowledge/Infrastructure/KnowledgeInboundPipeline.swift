import Foundation

/// 入站合并：Pull 结果 → 领域快照 → repository remote-apply。
/// 严格不生成 Outbox（否则会形成回声同步）；返回本页发生正文变化的 document_id，供上层调度 Chunk/Embedding 重建。
struct KnowledgeInboundPipeline: Sendable {
    private let repository: any KnowledgeRepository
    private let mergePolicy: KnowledgeMergePolicy

    nonisolated init(repository: any KnowledgeRepository, mergePolicy: KnowledgeMergePolicy = KnowledgeMergePolicy()) {
        self.repository = repository
        self.mergePolicy = mergePolicy
    }

    @discardableResult
    func applyRemotePage(_ dtos: [KnowledgeRemoteDocumentDTO]) async -> [UUID] {
        guard dtos.isEmpty == false else { return [] }
        let snapshots = dtos.map(KnowledgeSyncDTOMapper.remoteSnapshot(from:))
        let activeOutboxIDs = await repository.documentIDsWithActiveOutbox()
        let applicable = mergePolicy.snapshotsToApply(snapshots, activeOutboxDocumentIDs: activeOutboxIDs)
        guard applicable.isEmpty == false else { return [] }
        return await repository.applyRemoteDocuments(applicable)
    }
}
