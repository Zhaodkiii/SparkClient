import Foundation

// MARK: - 知识库领域模型
//
// 与 Core Data 中的 KnowledgeDocumentEntity / KnowledgeChunkEntity 一一对应，
// 供【业务用例层】和【UI展示层】使用；不包含旧版 PromptRepo 数据迁移逻辑。

// MARK: - 文档作用域（个人 / 绑定智能体）
/// 知识库文档的作用域：个人私有 / 绑定到某个智能体
enum KnowledgeDocumentScope: String, Codable, CaseIterable, Sendable {
    case personal       // 个人私有文档
    case agentBound     // 绑定到智能体的文档
}

// MARK: - 文档来源
/// 文档来源：用户手动创建 / 聊天工具自动创建
enum KnowledgeDocumentSource: String, Codable, CaseIterable, Sendable {
    case user    // 用户手动创建
    case tool    // 工具/自动化流程创建
}

// MARK: - 知识库文档（主模型）
/// 知识库文档（对应 Core Data 文档实体）
/// 代表一篇完整的用户上传/创建的文档
struct KnowledgeDocument: Identifiable, Equatable, Sendable {
    let id: UUID                          // 文档唯一ID
    let title: String                     // 文档标题
    let content: String                   // 文档完整内容
    let excerpt: String                   // 文档摘要/简介
    let scope: KnowledgeDocumentScope    // 作用域（个人/智能体）
    let boundModelID: String?            // 绑定的智能体ID（仅 agentBound 有效）
    let source: KnowledgeDocumentSource  // 来源（用户/工具）
    let chunkCount: Int                  // 文本切块数量
    let isEmbeddingIndexed: Bool         // 是否已完成向量索引（嵌入处理）
    let lastEmbeddingModelName: String?  // 最后一次向量化使用的模型名称
    let createdAt: Date                  // 创建时间
    let updatedAt: Date                  // 更新时间

    /// 列表页展示用副标题：优先使用摘要，没有则取内容预览
    var listSubtitle: String {
        excerpt.isEmpty ? content.previewText(limit: 96) : excerpt
    }
}

// MARK: - 文档切块（向量检索最小单元）
/// 文档切块（对应 Core Data 切块实体）
/// 文档会被切分成多个块，用于向量检索
struct KnowledgeChunk: Identifiable, Equatable, Sendable {
    let id: UUID              // 切块唯一ID
    let documentID: UUID      // 所属文档ID
    let sequence: Int         // 切块顺序序号
    let content: String       // 切块文本内容
    let embedding: [Float]?   // 向量嵌入数据（主要用于调试/展示）
    let createdAt: Date       // 创建时间
    let updatedAt: Date       // 更新时间
}

// MARK: - 检索结果模型
/// 知识库搜索/检索结果
/// 用于 UI 展示匹配到的文档和相关性得分
struct KnowledgeSearchResult: Identifiable, Equatable, Sendable {
    let documentID: UUID              // 匹配到的文档ID
    let title: String                 // 文档标题
    let excerpt: String                // 文档摘要
    let matchedChunkSequence: Int?    // 命中的切块序号
    let score: Double                 // 相似度评分

    /// 遵守 Identifiable 协议，使用 documentID 作为唯一标识
    var id: UUID {
        documentID
    }
}

// MARK: - 文档草稿（创建/编辑时使用）
/// 文档草稿模型
/// 用于新建/编辑文档时临时存储数据，未持久化到数据库
struct KnowledgeDocumentDraft: Equatable, Sendable {
    var title: String                     // 标题
    var content: String                   // 内容
    var scope: KnowledgeDocumentScope     // 作用域
    var boundModelID: String?            // 绑定智能体ID
    var source: KnowledgeDocumentSource   // 来源

    // 带默认值的初始化方法
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

// MARK: - 字符串预览扩展
private extension String {
    /// 生成列表预览文本：替换换行/制表符 → 去空白 → 超长截取+省略号
    func previewText(limit: Int) -> String {
        // 替换换行、制表符为空格，清除首尾空白
        let normalized = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 不超限直接返回
        guard normalized.count > limit else { return normalized }
        // 超限截取并添加省略号
        return String(normalized.prefix(limit)) + "..."
    }
}
