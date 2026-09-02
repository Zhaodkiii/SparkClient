import Foundation

// MARK: - CHAT-000055 医院知识 Domain 模型
//
// 契约要点：
// - Manifest 是知识绑定的单一事实源（Q22），由 conversation context 下发。
// - 本地知识按「医院科普知识库 scope」组织（Q26），不按智能体维度存储。
// - 向量有效性门禁（Q33）：document 级 chunk.document_revision == document.revision，
//   KB 级 indexed_revision == revision 且 vectorStatus == current；不满足降级关键词检索。

/// Q26：知识数据组织的唯一 scope = 医院科普知识库 ID。
nonisolated struct HospitalKnowledgeScope: Hashable, Sendable, Codable {
    let knowledgeBaseID: UUID

    var storageKey: String { knowledgeBaseID.uuidString.lowercased() }
}

/// Q22：单个知识库在 Manifest 中的状态条目。
nonisolated struct HospitalKnowledgeManifestItem: Equatable, Sendable {
    let knowledgeBaseID: UUID
    let name: String
    let revision: Int64
    let vectorStatus: HospitalKnowledgeVectorStatus
    let indexedRevision: Int64?
    let updatedAt: Date?
    /// 服务端 KB 已删除（按解绑语义处理）。
    let isDeleted: Bool

    /// Q33 KB 级向量有效性：fresh 状态才可能走向量召回。
    var isVectorFresh: Bool {
        vectorStatus == .current
            && indexedRevision != nil
            && indexedRevision == revision
    }
}

/// Q22：会话级知识 Manifest。
nonisolated struct HospitalAgentKnowledgeManifest: Equatable, Sendable {
    let manifestRevision: Int64
    let generatedAt: Date?
    let agentID: UUID
    let hospitalID: UUID
    let items: [HospitalKnowledgeManifestItem]

    func item(for knowledgeBaseID: UUID) -> HospitalKnowledgeManifestItem? {
        items.first { $0.knowledgeBaseID == knowledgeBaseID }
    }
}

nonisolated enum HospitalKnowledgeVectorStatus: String, Sendable, Codable {
    case notBuilt = "not_built"
    case building
    case current
    case stale

    init(rawOrUnknown rawValue: String) {
        self = HospitalKnowledgeVectorStatus(rawValue: rawValue) ?? .notBuilt
    }
}

/// Q25：单个 scope 的本地同步状态。
nonisolated struct HospitalKnowledgeSyncState: Equatable, Sendable, Codable {
    var scopeKey: String
    var lastManifestRevision: Int64?
    var lastRevision: Int64?
    var lastIndexedRevision: Int64?
    var cursor: String?
    var hasCompletedInitialFullSync: Bool
    var lastSyncAt: Date?
    var lastSyncResult: SyncResult?
    /// Q34：当前仍绑定该 scope 的智能体集合（引用计数语义）。
    /// 某智能体 Manifest 中该 scope 消失时将其移除；集合变空即物理清除 scope。
    /// 旧版本持久化数据缺省为 nil，按空集合处理。
    var boundAgentIDs: Set<UUID>?

    enum SyncResult: String, Sendable, Codable {
        case success
        case failed
    }
}

/// 本地缓存的知识文档（正文 + 元数据）。
nonisolated struct HospitalKnowledgeDocumentRecord: Equatable, Sendable, Codable {
    let documentID: UUID
    let title: String
    let content: String
    let excerpt: String
    let revision: Int64
    let updatedAt: Date?
}

/// 本地缓存的知识向量块。
nonisolated struct HospitalKnowledgeChunkRecord: Equatable, Sendable, Codable {
    let chunkID: UUID
    let documentID: UUID
    let sequence: Int
    let content: String
    let contentHash: String
    let documentRevision: Int64
    let vector: [Float]
    let embeddingBindingID: String?
}

/// Q32/Q33：每次检索的明确模式。
nonisolated enum HospitalKnowledgeSearchMode: String, Sendable, Equatable {
    case vector
    case keywordFallback
    case metadataOnly
}

/// 单条检索命中。
nonisolated struct HospitalKnowledgeSearchHit: Equatable, Sendable {
    let documentID: UUID
    let title: String
    let snippet: String
    let score: Double
    let documentRevision: Int64
    let isStaleContent: Bool
}

/// 一次检索的完整结果（Q32：必须带回模式与降级原因）。
nonisolated struct HospitalKnowledgeSearchResult: Equatable, Sendable {
    let mode: HospitalKnowledgeSearchMode
    let hits: [HospitalKnowledgeSearchHit]
    let fallbackReason: String?

    static let emptyKeyword = HospitalKnowledgeSearchResult(mode: .keywordFallback, hits: [], fallbackReason: nil)
}

// MARK: - 会话能力（Q22/Q27/Q28）

/// context 下发的会话能力；发送入口的唯一门禁事实源。
nonisolated struct HospitalConversationCapabilities: Equatable, Sendable {
    let canReadCachedHistory: Bool
    let canPullRemoteMessages: Bool
    let canSendMessage: Bool
    let canSyncKnowledge: Bool
    let readOnlyReason: String?

    /// 本地默认（context 未回源前）：允许发送、允许同步。
    static let optimisticDefault = HospitalConversationCapabilities(
        canReadCachedHistory: true,
        canPullRemoteMessages: true,
        canSendMessage: true,
        canSyncKnowledge: true,
        readOnlyReason: nil
    )

    /// Q28：成员权限撤回——历史可读、禁止发送、停止知识同步。
    static let memberAccessRevoked = HospitalConversationCapabilities(
        canReadCachedHistory: true,
        canPullRemoteMessages: false,
        canSendMessage: false,
        canSyncKnowledge: false,
        readOnlyReason: "member_access_revoked"
    )
}
