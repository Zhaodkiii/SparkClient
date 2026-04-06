import Foundation

/// 知识库持久化抽象：由 `CoreDataKnowledgeRepository` 实现，供各用例注入。
protocol KnowledgeRepository: Sendable {
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
}
