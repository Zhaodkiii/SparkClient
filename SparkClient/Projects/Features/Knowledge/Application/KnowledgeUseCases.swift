import Foundation

// MARK: - 知识库用例
//
// 遵循项目惯例：ViewModel 只依赖用例，用例只依赖 `KnowledgeRepository`。

struct LoadKnowledgeListUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(query: String? = nil) async throws -> [KnowledgeDocument] {
        try await repository.loadDocuments(matching: query)
    }
}

struct LoadKnowledgeDocumentUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(id: UUID) async throws -> KnowledgeDocument? {
        try await repository.loadDocument(id: id)
    }
}

struct CreateKnowledgeDocumentUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(_ draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        try await repository.createDocument(draft)
    }
}

struct UpdateKnowledgeDocumentUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(id: UUID, draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        try await repository.updateDocument(id: id, draft: draft)
    }
}

struct DeleteKnowledgeDocumentUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(id: UUID) async throws {
        try await repository.deleteDocument(id: id)
    }
}

struct SearchKnowledgeUseCase: Sendable {
    let repository: any KnowledgeRepository
    let aiConfigCenter: AIConfigCenter
    let embeddingClient: any KnowledgeEmbeddingClient

    func execute(query: String, limit: Int = 8) async throws -> [KnowledgeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let hasVectors = try await repository.hasVectorIndexedChunks()
        if hasVectors {
            do {
                let bundles = try await aiConfigCenter.effectiveScenarioBundles()
                let resolved = try KnowledgeEmbeddingResolution.resolve(modelName: nil, in: bundles)
                let vectors = try await embeddingClient.embed(
                    texts: [trimmed],
                    modelName: resolved.apiModelName,
                    apiKey: resolved.apiKey,
                    endpointURL: resolved.embeddingsURL
                )
                if let q = vectors.first, q.isEmpty == false {
                    return try await repository.search(query: trimmed, limit: limit, queryEmbedding: q)
                }
            } catch {
                // 查询嵌入失败时回退词法，保证 ToolHub 仍可用。
            }
        }
        return try await repository.search(query: trimmed, limit: limit, queryEmbedding: nil)
    }
}

struct ReindexKnowledgeDocumentUseCase: Sendable {
    let repository: any KnowledgeRepository

    func execute(id: UUID) async throws -> KnowledgeDocument {
        try await repository.rebuildIndex(id: id)
    }
}
