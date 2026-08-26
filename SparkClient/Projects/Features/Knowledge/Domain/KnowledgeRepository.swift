import Foundation

/// 知识库持久化抽象：由 `CoreDataKnowledgeRepository` 实现，供各用例注入。
nonisolated protocol KnowledgeRepository: Sendable {
    func loadDocuments(matching query: String?) async throws -> [KnowledgeDocument]
    func loadDocument(id: UUID) async throws -> KnowledgeDocument?
    func createDocument(_ draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument
    func updateDocument(id: UUID, draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument
    func rebuildIndex(id: UUID) async throws -> KnowledgeDocument
    func deleteDocument(id: UUID) async throws
    /// 是否存在至少一条带 `vectorData` 的切块（用于决定是否走语义检索）。
    func hasVectorIndexedChunks() async throws -> Bool
    /// 用 Markdown 切块后的文本与向量替换文档的切块行，并标记已向量化。
    func replaceDocumentChunksWithEmbeddings(
        documentID: UUID,
        chunkTexts: [String],
        embeddings: [[Float]],
        modelName: String
    ) async throws -> KnowledgeDocument
    /// `queryEmbedding` 非空时，对带向量的切块做余弦相似度 Top-K；否则回退词法打分。
    func search(query: String, limit: Int, queryEmbedding: [Float]?) async throws -> [KnowledgeSearchResult]

    // MARK: - 多设备同步（工单 KNOWLEDGE-SYNC-000001）

    /// 待发送/待重试的 Outbox 记录；`limit` 对齐服务端单批上限。
    func loadPendingOutbox(limit: Int) async -> [KnowledgeOutboxRecord]
    /// 当前存在未终态 Outbox（pending/sending/failedRetryable）的 document_id 集合；
    /// Pull 合并时必须跳过这些文档，避免吞掉尚未上送的本地编辑。
    func documentIDsWithActiveOutbox() async -> Set<UUID>
    func markOutboxSending(mutationIDs: [UUID]) async
    /// Push 被接受/回放成功：清除该 mutation，并把服务端权威快照写回主文档。
    func markOutboxAcceptedAndApplyServerFields(
        mutationID: UUID,
        documentID: UUID,
        revision: Int64,
        serverUpdatedAt: Date,
        contentHash: String
    ) async
    /// 409 冲突：应用响应中的服务端最新快照覆盖本地主文档，移除该 mutation，不再重试。
    func resolveConflictWithServerSnapshot(mutationID: UUID, snapshot: KnowledgeRemoteDocumentSnapshot) async
    func markOutboxFailedRetryable(mutationID: UUID, errorCode: String, nextAttemptAt: Date) async
    func markOutboxFailedPermanent(mutationID: UUID, errorCode: String) async

    /// Remote apply：按 `document_id` upsert，不生成 Outbox；返回本轮实际发生正文变化的文档 ID（供 Chunk 重建调度）。
    @discardableResult
    func applyRemoteDocuments(_ documents: [KnowledgeRemoteDocumentSnapshot]) async -> [UUID]

    func loadSyncCursor() async -> String?
    func saveSyncCursor(_ value: String?) async
}
