import Foundation

/// 对单篇文档做 Markdown 切块、批量请求嵌入并写回 `vectorData`（与 UI「构建以允许聊天召回」一致）。
struct BuildKnowledgeEmbeddingsUseCase: Sendable {
    let repository: any KnowledgeRepository
    let aiConfigCenter: AIConfigCenter
    let embeddingClient: any KnowledgeEmbeddingClient

    func execute(documentID: UUID, modelName: String) async throws -> KnowledgeDocument {
        let snapshot = await aiConfigCenter.currentSnapshot()
        let resolved = try KnowledgeEmbeddingResolution.resolve(modelName: modelName, snapshot: snapshot)

        guard let doc = try await repository.loadDocument(id: documentID) else {
            throw BuildError.documentNotFound
        }

        let chunkTexts = KnowledgeChunking.chunksForEmbedding(from: doc.content)
        guard chunkTexts.isEmpty == false else {
            throw BuildError.emptyContent
        }

        var allEmbeddings: [[Float]] = []
        allEmbeddings.reserveCapacity(chunkTexts.count)
        let batchSize = 10
        var start = 0
        while start < chunkTexts.count {
            let end = min(start + batchSize, chunkTexts.count)
            let batch = Array(chunkTexts[start..<end])
            let vectors = try await embeddingClient.embed(
                texts: batch,
                modelName: resolved.apiModelName,
                apiKey: resolved.apiKey,
                endpointURL: resolved.embeddingsURL
            )
            allEmbeddings.append(contentsOf: vectors)
            start = end
        }

        guard allEmbeddings.count == chunkTexts.count else {
            throw BuildError.embeddingCountMismatch
        }

        return try await repository.replaceDocumentChunksWithEmbeddings(
            documentID: documentID,
            chunkTexts: chunkTexts,
            embeddings: allEmbeddings,
            modelName: modelName
        )
    }

    enum BuildError: LocalizedError {
        case documentNotFound
        case emptyContent
        case embeddingCountMismatch

        var errorDescription: String? {
            switch self {
            case .documentNotFound:
                return "未找到知识文档。"
            case .emptyContent:
                return "正文为空，无法切块嵌入。"
            case .embeddingCountMismatch:
                return "嵌入返回数量与切块不一致。"
            }
        }
    }
}
