import Foundation

// MARK: - 知识库领域模型
//
// 与 Core Data 中的 KnowledgeDocumentEntity / KnowledgeChunkEntity 一一对应，
// 供【业务用例层】和【UI展示层】使用；不包含旧版 PromptRepo 数据迁移逻辑。

// MARK: - 文档作用域（个人 / 绑定智能体）
/// 知识库文档的作用域：个人私有 / 绑定到某个智能体
nonisolated enum KnowledgeDocumentScope: String, Codable, CaseIterable, Sendable {
    case personal       // 个人私有文档
    case agentBound     // 绑定到智能体的文档
}

// MARK: - 文档来源
/// 文档来源：用户手动创建 / 聊天工具自动创建
nonisolated enum KnowledgeDocumentSource: String, Codable, CaseIterable, Sendable {
    case user    // 用户手动创建
    case tool    // 工具/自动化流程创建
}

// MARK: - 多设备同步状态（工单 5.9）
/// 知识文档的多设备同步状态；由本地文档 + Outbox + Engine in-flight 状态投影得出，
/// 不由 ViewModel 自行猜测。列表卡片据此展示同步标识。
nonisolated enum KnowledgeSyncState: String, Codable, CaseIterable, Sendable {
    case localOnly          // 旧数据/新建文档尚未形成有效同步 ACK
    case pending             // 已有待发送 mutation
    case syncing             // 当前 mutation 正在发送，或正在应用远端版本
    case synced              // 无待发 mutation，已知 revision 与最近服务端快照一致
    case failedRetryable     // 网络/429/5xx/Token 暂时不可用，自动退避重试
    case failedPermanent     // payload 非法/超配额/幂等契约冲突，需用户修正后生成新 mutation
    case resolvedByServer    // revision/删除冲突，已按服务端快照收敛，短暂展示后转 synced
}

// MARK: - 同步 mutation 操作类型
nonisolated enum KnowledgeSyncOperation: String, Codable, CaseIterable, Sendable {
    case create
    case update
    case delete
    case restore
}

// MARK: - Outbox 行内部状态机（`KnowledgeSyncOutboxEntity.stateRaw`）
nonisolated enum KnowledgeOutboxState: String, Codable, CaseIterable, Sendable {
    case pending
    case sending
    case failedRetryable
    case failedPermanent
}

// MARK: - 知识库文档（主模型）
/// 知识库文档（对应 Core Data 文档实体）
/// 代表一篇完整的用户上传/创建的文档
nonisolated struct KnowledgeDocument: Identifiable, Equatable, Sendable {
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

    // MARK: 同步元数据（工单 8.1）
    let knowledgeBaseID: UUID?           // 服务端默认知识库 ID；未同步前为 nil
    let serverRevision: Int64            // 最后 ACK/Pull 的服务端 revision；本地未同步旧数据为 0
    let serverUpdatedAt: Date?           // 远端活动时间，仅用于展示/诊断，不覆盖本地 updatedAt 语义
    let isDeleted: Bool                  // 本地墓碑/远端墓碑
    let contentHash: String              // 本地 no-op 判断/诊断用
    let syncState: KnowledgeSyncState    // 列表卡片同步状态投影
    let lastSyncErrorCode: String?       // 脱敏稳定错误码；成功后清除

    init(
        id: UUID,
        title: String,
        content: String,
        excerpt: String,
        scope: KnowledgeDocumentScope,
        boundModelID: String?,
        source: KnowledgeDocumentSource,
        chunkCount: Int,
        isEmbeddingIndexed: Bool,
        lastEmbeddingModelName: String?,
        createdAt: Date,
        updatedAt: Date,
        knowledgeBaseID: UUID? = nil,
        serverRevision: Int64 = 0,
        serverUpdatedAt: Date? = nil,
        isDeleted: Bool = false,
        contentHash: String = "",
        syncState: KnowledgeSyncState = .localOnly,
        lastSyncErrorCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.excerpt = excerpt
        self.scope = scope
        self.boundModelID = boundModelID
        self.source = source
        self.chunkCount = chunkCount
        self.isEmbeddingIndexed = isEmbeddingIndexed
        self.lastEmbeddingModelName = lastEmbeddingModelName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.knowledgeBaseID = knowledgeBaseID
        self.serverRevision = serverRevision
        self.serverUpdatedAt = serverUpdatedAt
        self.isDeleted = isDeleted
        self.contentHash = contentHash
        self.syncState = syncState
        self.lastSyncErrorCode = lastSyncErrorCode
    }

    /// 列表页展示用副标题：优先使用摘要，没有则取内容预览
    var listSubtitle: String {
        excerpt.isEmpty ? content.previewText(limit: 96) : excerpt
    }
}

// MARK: - 待发同步队列条目（Outbox 投影，供 Sync 基础设施使用）
nonisolated struct KnowledgeOutboxRecord: Identifiable, Equatable, Sendable {
    let mutationID: UUID
    let documentID: UUID
    let operation: KnowledgeSyncOperation
    let baseRevision: Int64
    let payload: Data
    let requestHash: String
    let attemptCount: Int32
    let nextAttemptAt: Date?

    var id: UUID { mutationID }
}

// MARK: - Pull 结果的远端文档快照（remote apply 专用，不经过 Outbox）
nonisolated struct KnowledgeRemoteDocumentSnapshot: Equatable, Sendable {
    let id: UUID
    let knowledgeBaseID: UUID?
    let title: String
    let content: String
    let excerpt: String
    let scope: KnowledgeDocumentScope
    let boundModelID: String?
    let source: KnowledgeDocumentSource
    let revision: Int64
    let contentHash: String
    let isDeleted: Bool
    let deletedAt: Date?
    let serverUpdatedAt: Date
}

// MARK: - 文档切块（向量检索最小单元）
/// 文档切块（对应 Core Data 切块实体）
/// 文档会被切分成多个块，用于向量检索
nonisolated struct KnowledgeChunk: Identifiable, Equatable, Sendable {
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
nonisolated struct KnowledgeSearchResult: Identifiable, Equatable, Sendable {
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
nonisolated struct KnowledgeDocumentDraft: Equatable, Sendable {
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
nonisolated private extension String {
    /// 生成列表预览文本：替换换行/制表符 → 去空白 → 超长截取+省略号
    nonisolated func previewText(limit: Int) -> String {
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
