import Foundation

/// 对单篇文档做 Markdown 切块、批量请求嵌入并写回 `vectorData`（与 UI「构建以允许聊天召回」一致）。
import Foundation

/// 「构建知识库向量嵌入」用例
/// 核心职责：为指定知识文档生成向量嵌入（Embedding）
/// 流程：加载文档 → 文本切块 → 批量调用Embedding接口 → 保存向量数据 → 更新文档索引状态
struct BuildKnowledgeEmbeddingsUseCase: Sendable {

    // MARK: - 依赖
    /// 知识库数据仓库（数据层接口）
    let repository: any KnowledgeRepository
    /// AI 配置中心（获取模型、密钥、接口地址）
    let aiConfigCenter: AIConfigCenter
    /// 向量嵌入客户端（调用AI服务生成向量）
    let embeddingClient: any KnowledgeEmbeddingClient

    // MARK: - 执行用例（核心方法）
    /// 为指定文档构建向量嵌入
    /// - Parameters:
    ///   - documentID: 文档ID
    ///   - modelName: 使用的嵌入模型名称
    /// - Returns: 更新后的文档对象
    /// - Throws: 构建过程中出现的错误
    func execute(documentID: UUID, modelName: String) async throws -> KnowledgeDocument {
        // 1. 获取当前生效的AI模型配置束
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        
        // 2. 解析并校验嵌入模型配置（模型名、API Key、接口地址）
        let resolved = try KnowledgeEmbeddingResolution.resolve(modelName: modelName, in: bundles)

        // 3. 从仓库加载目标文档
        guard let doc = try await repository.loadDocument(id: documentID) else {
            throw BuildError.documentNotFound
        }

        // 4. 对文档内容进行文本切块（生成适合嵌入的文本片段）
        let chunkTexts = KnowledgeChunking.chunksForEmbedding(from: doc.content)
        
        // 校验内容不能为空
        guard chunkTexts.isEmpty == false else {
            throw BuildError.emptyContent
        }

        // 5. 批量调用嵌入接口，生成向量
        var allEmbeddings: [[Float]] = []
        // 提前分配容量，提升性能
        allEmbeddings.reserveCapacity(chunkTexts.count)
        
        // 批处理大小：每次请求10块，避免单次请求过大
        let batchSize = 10
        var start = 0
        
        while start < chunkTexts.count {
            let end = min(start + batchSize, chunkTexts.count)
            let batch = Array(chunkTexts[start..<end])
            
            // 调用AI接口，获取文本向量
            let vectors = try await embeddingClient.embed(
                texts: batch,
                modelName: resolved.apiModelName,
                apiKey: resolved.apiKey,
                endpointURL: resolved.embeddingsURL
            )
            
            // 收集返回的向量
            allEmbeddings.append(contentsOf: vectors)
            start = end
        }

        // 6. 校验：向量数量必须与文本切块数量完全一致
        guard allEmbeddings.count == chunkTexts.count else {
            throw BuildError.embeddingCountMismatch
        }

        // 7. 替换数据库中的旧切块与向量，保存新数据，并返回更新后的文档
        return try await repository.replaceDocumentChunksWithEmbeddings(
            documentID: documentID,
            chunkTexts: chunkTexts,
            embeddings: allEmbeddings,
            modelName: modelName
        )
    }

    // MARK: - 错误类型
    /// 构建向量嵌入的错误枚举
    enum BuildError: LocalizedError {
        case documentNotFound       // 文档不存在
        case emptyContent           // 文档内容为空
        case embeddingCountMismatch // 向量数量与切块数量不匹配

        /// 错误本地化描述
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
