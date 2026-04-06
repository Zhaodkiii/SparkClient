import Foundation

// MARK: - 知识库领域模型
//
// 与 `Core Data` 中的 `KnowledgeDocumentEntity` / `KnowledgeChunkEntity` 对应，
// 供 Application 层用例与 Presentation 层展示使用；不包含旧版 PromptRepo 迁移逻辑。

enum KnowledgeDocumentScope: String, Codable, CaseIterable, Sendable {
    case personal
    case agentBound
}

/// 文档来源：用户手写或通过聊天工具创建。
enum KnowledgeDocumentSource: String, Codable, CaseIterable, Sendable {
    case user
    case tool
}

struct KnowledgeDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let excerpt: String
    let scope: KnowledgeDocumentScope
    let boundModelID: String?
    let source: KnowledgeDocumentSource
    let chunkCount: Int
    /// 是否已用嵌入模型构建向量切块（与 `KnowledgeChunkEntity.vectorData` 一致）。
    let isEmbeddingIndexed: Bool
    /// 最近一次成功向量索引使用的模型 `name`（来自 `AllModels.name`）。
    let lastEmbeddingModelName: String?
    let createdAt: Date
    let updatedAt: Date

    var listSubtitle: String {
        excerpt.isEmpty ? content.previewText(limit: 96) : excerpt
    }
}

struct KnowledgeChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let documentID: UUID
    let sequence: Int
    let content: String
    /// 可选：从 `vectorData` 解码的向量，用于调试或高级展示；检索主要在仓库内完成。
    let embedding: [Float]?
    let createdAt: Date
    let updatedAt: Date
}

struct KnowledgeSearchResult: Identifiable, Equatable, Sendable {
    let documentID: UUID
    let title: String
    let excerpt: String
    let matchedChunkSequence: Int?
    let score: Double

    var id: UUID {
        documentID
    }
}

struct KnowledgeDocumentDraft: Equatable, Sendable {
    var title: String
    var content: String
    var scope: KnowledgeDocumentScope
    var boundModelID: String?
    var source: KnowledgeDocumentSource

    init(
        title: String = "",
        content: String = "",
        scope: KnowledgeDocumentScope = .personal,
        boundModelID: String? = nil,
        source: KnowledgeDocumentSource = .user
    ) {
        self.title = title
        self.content = content
        self.scope = scope
        self.boundModelID = boundModelID
        self.source = source
    }
}

private extension String {
    func previewText(limit: Int) -> String {
        let normalized = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }
}
