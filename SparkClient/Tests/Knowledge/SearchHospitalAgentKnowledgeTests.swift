#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000055 Q32/Q33：向量有效性门禁 + 关键词降级检索。
final class SearchHospitalAgentKnowledgeTests: XCTestCase {
    private let accountID: Int64 = 42

    private func makeItem(
        revision: Int64,
        vectorStatus: HospitalKnowledgeVectorStatus,
        indexedRevision: Int64?
    ) -> HospitalKnowledgeManifestItem {
        HospitalKnowledgeManifestItem(
            knowledgeBaseID: UUID(),
            name: "KB",
            revision: revision,
            vectorStatus: vectorStatus,
            indexedRevision: indexedRevision,
            updatedAt: nil,
            isDeleted: false
        )
    }

    private func makeDocument(
        id: UUID = UUID(),
        title: String = "文档",
        content: String = "正文",
        revision: Int64 = 1,
        updatedAt: Date? = nil
    ) -> HospitalKnowledgeDocumentRecord {
        HospitalKnowledgeDocumentRecord(
            documentID: id,
            title: title,
            content: content,
            excerpt: "",
            revision: revision,
            updatedAt: updatedAt
        )
    }

    private func makeChunk(
        documentID: UUID,
        documentRevision: Int64,
        vector: [Float]
    ) -> HospitalKnowledgeChunkRecord {
        HospitalKnowledgeChunkRecord(
            chunkID: UUID(),
            documentID: documentID,
            sequence: 0,
            content: "向量片段",
            contentHash: "hash",
            documentRevision: documentRevision,
            vector: vector,
            embeddingBindingID: nil
        )
    }

    private func seed(
        _ repository: HospitalKnowledgeInMemoryRepository,
        scope: HospitalKnowledgeScope,
        documents: [HospitalKnowledgeDocumentRecord],
        chunks: [HospitalKnowledgeChunkRecord]
    ) {
        repository.replaceScope(
            scope,
            documents: documents,
            chunks: chunks,
            accountID: accountID
        )
    }

    // MARK: - 空查询 → metadataOnly

    func testEmptyQueryReturnsMetadataOnly() {
        let scope = HospitalKnowledgeScope(knowledgeBaseID: UUID())
        let repository = HospitalKnowledgeInMemoryRepository()
        let old = makeDocument(title: "旧文档", updatedAt: Date(timeIntervalSince1970: 100))
        let new = makeDocument(title: "新文档", updatedAt: Date(timeIntervalSince1970: 200))
        seed(repository, scope: scope, documents: [old, new], chunks: [])
        let useCase = SearchHospitalAgentKnowledgeUseCase(repository: repository)

        let result = useCase.execute(SearchHospitalAgentKnowledgeUseCase.Input(
            scope: scope,
            accountID: accountID,
            query: "   ",
            manifestItem: nil
        ))

        XCTAssertEqual(result.mode, .metadataOnly)
        XCTAssertEqual(result.hits.map(\.documentID), [new.documentID, old.documentID])
    }

    // MARK: - 向量门禁全过 → vector 模式

    func testVectorSearchWhenManifestFreshAndChunkCurrent() {
        let scope = HospitalKnowledgeScope(knowledgeBaseID: UUID())
        let repository = HospitalKnowledgeInMemoryRepository()
        let document = makeDocument(revision: 3)
        seed(
            repository,
            scope: scope,
            documents: [document],
            chunks: [makeChunk(documentID: document.documentID, documentRevision: 3, vector: [1, 0])]
        )
        let useCase = SearchHospitalAgentKnowledgeUseCase(repository: repository)
        let item = makeItem(revision: 3, vectorStatus: .current, indexedRevision: 3)

        let result = useCase.execute(SearchHospitalAgentKnowledgeUseCase.Input(
            scope: scope,
            accountID: accountID,
            query: "查询",
            manifestItem: item,
            queryEmbedding: [1, 0]
        ))

        XCTAssertEqual(result.mode, .vector)
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.hits[0].score, 1, accuracy: 0.0001)
    }

    // MARK: - 文档级门禁：chunk revision 过期 → 降级关键词

    func testStaleChunkRevisionFallsBackToKeyword() {
        let scope = HospitalKnowledgeScope(knowledgeBaseID: UUID())
        let repository = HospitalKnowledgeInMemoryRepository()
        // 正文已升到 revision 2，但向量还是 revision 1 的旧向量——不得冒充。
        let document = makeDocument(title: "高血压用药", content: "高血压 随访", revision: 2)
        seed(
            repository,
            scope: scope,
            documents: [document],
            chunks: [makeChunk(documentID: document.documentID, documentRevision: 1, vector: [1, 0])]
        )
        let useCase = SearchHospitalAgentKnowledgeUseCase(repository: repository)
        let item = makeItem(revision: 2, vectorStatus: .current, indexedRevision: 2)

        let result = useCase.execute(SearchHospitalAgentKnowledgeUseCase.Input(
            scope: scope,
            accountID: accountID,
            query: "高血压",
            manifestItem: item,
            queryEmbedding: [1, 0]
        ))

        XCTAssertEqual(result.mode, .keywordFallback)
        XCTAssertEqual(result.hits.map(\.documentID), [document.documentID])
    }

    // MARK: - KB 级门禁：manifest 向量过期/缺失 → 关键词降级

    func testStaleManifestVectorStatusFallsBackToKeyword() {
        let scope = HospitalKnowledgeScope(knowledgeBaseID: UUID())
        let repository = HospitalKnowledgeInMemoryRepository()
        let document = makeDocument(title: "糖尿病饮食", content: "血糖 控制", revision: 1)
        seed(
            repository,
            scope: scope,
            documents: [document],
            chunks: [makeChunk(documentID: document.documentID, documentRevision: 1, vector: [1, 0])]
        )
        let useCase = SearchHospitalAgentKnowledgeUseCase(repository: repository)
        // indexedRevision 落后于 revision → 向量非 fresh。
        let item = makeItem(revision: 2, vectorStatus: .stale, indexedRevision: 1)

        let result = useCase.execute(SearchHospitalAgentKnowledgeUseCase.Input(
            scope: scope,
            accountID: accountID,
            query: "血糖",
            manifestItem: item,
            queryEmbedding: [1, 0]
        ))

        XCTAssertEqual(result.mode, .keywordFallback)
        XCTAssertEqual(result.hits.map(\.documentID), [document.documentID])
        XCTAssertNotNil(result.fallbackReason)
    }

    // MARK: - 降级结果标注本地内容可能过期

    func testKeywordFallbackMarksContentNewerThanManifestAsStale() {
        let scope = HospitalKnowledgeScope(knowledgeBaseID: UUID())
        let repository = HospitalKnowledgeInMemoryRepository()
        // 本地正文 revision(3) 已超出 manifest 声明(2) → 内容可能未获服务端确认。
        let document = makeDocument(title: "出院指导", content: "复查 时间", revision: 3)
        seed(repository, scope: scope, documents: [document], chunks: [])
        let useCase = SearchHospitalAgentKnowledgeUseCase(repository: repository)
        let item = makeItem(revision: 2, vectorStatus: .notBuilt, indexedRevision: nil)

        let result = useCase.execute(SearchHospitalAgentKnowledgeUseCase.Input(
            scope: scope,
            accountID: accountID,
            query: "复查",
            manifestItem: item
        ))

        XCTAssertEqual(result.mode, .keywordFallback)
        XCTAssertEqual(result.hits.first?.isStaleContent, true)
    }
}
#endif
