import Foundation

nonisolated struct HospitalCarePageDTO<Item: Codable & Sendable>: Codable, Sendable {
    let items: [Item]
    let pagination: HospitalCarePaginationDTO?
}

nonisolated struct HospitalCarePaginationDTO: Codable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
}

nonisolated struct HospitalPublicDTO: Codable, Sendable {
    let id: UUID
    let code: String?
    let name: String
    let shortName: String?
    let introduction: String?
    let status: String
}

nonisolated struct HospitalDepartmentPublicDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int?
}

nonisolated struct HospitalDoctorPublicDTO: Codable, Sendable {
    let id: UUID
    let displayName: String
    let title: String?
    let specialties: [String]?
    let introduction: String?
    let avatarUrl: String?
}

nonisolated struct HospitalAgentPublicDTO: Codable, Sendable {
    let id: UUID
    let hospitalId: UUID
    let name: String
    let publicSummary: String?
    let greeting: String?
    let serviceBoundary: String?
    let publicationStatus: String?
    let publishedAt: Date?
    let department: HospitalDepartmentPublicDTO?
    let doctor: HospitalDoctorPublicDTO
}

nonisolated struct HospitalConversationAgentDTO: Codable, Sendable {
    let id: UUID
    let name: String?
    let publicationStatus: String?
}

nonisolated struct HospitalConversationDTO: Codable, Sendable {
    let threadId: UUID
    let agent: HospitalConversationAgentDTO
    let memberId: Int?
    let hospital: HospitalPublicDTO?
}

nonisolated struct HospitalCreateConversationRequestDTO: Encodable, Sendable {
    let agentId: UUID
    let memberId: Int
}

nonisolated struct HospitalCreateConversationResponseDTO: Codable, Sendable {
    let threadId: UUID
    let conversation: HospitalConversationDTO
}

/// GET /api/v1/hospital-care/conversations/{thread_id}/context/ 的响应。
/// 404 表示该 Thread 不是医院会话（客户端据此按普通会话处理）。
nonisolated struct HospitalConversationContextDTO: Codable, Sendable {
    let threadId: UUID
    let hospital: HospitalPublicDTO
    let agent: HospitalConversationAgentDTO
    let memberId: Int?
    /// CHAT-000055 Q22/Q27：会话能力（缺省字段容忍旧服务端）。
    let capabilities: HospitalConversationCapabilitiesDTO?
    /// CHAT-000055 Q22：知识 Manifest；缺省/null 表示无绑定或已全量下线。
    let knowledgeManifest: HospitalKnowledgeManifestDTO?
}

nonisolated struct HospitalConversationCapabilitiesDTO: Codable, Sendable {
    let canReadCachedHistory: Bool?
    let canPullRemoteMessages: Bool?
    let canSendMessage: Bool?
    let canSyncKnowledge: Bool?
    let readOnlyReason: String?
}

nonisolated struct HospitalKnowledgeManifestDTO: Codable, Sendable {
    let manifestRevision: Int64
    let generatedAt: Date?
    let agentId: UUID
    let hospitalId: UUID
    let knowledgeBases: [HospitalKnowledgeManifestItemDTO]
}

nonisolated struct HospitalKnowledgeManifestItemDTO: Codable, Sendable {
    let knowledgeBaseId: UUID
    let name: String
    let revision: Int64
    let vectorStatus: String
    let indexedRevision: Int64?
    let updatedAt: Date?
    let deleted: Bool?
}

// MARK: - CHAT-000055 Q23 医院知识只读增量 pull

/// GET /api/v1/hospital-care/knowledge-bases/{knowledge_base_id}/sync/pull/ 的响应。
nonisolated struct HospitalKnowledgePullPageDTO: Codable, Sendable {
    let knowledgeBaseId: UUID
    let revision: Int64
    let vectorStatus: String
    let indexedRevision: Int64?
    let cursor: String?
    let hasMore: Bool
    let documents: [HospitalKnowledgeDocumentDTO]
}

nonisolated struct HospitalKnowledgeDocumentDTO: Codable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let excerpt: String
    let revision: Int64
    let isDeleted: Bool
    let updatedAt: Date?
    let chunks: [HospitalKnowledgeChunkDTO]
}

nonisolated struct HospitalKnowledgeChunkDTO: Codable, Sendable {
    let id: UUID
    let sequence: Int
    let content: String
    let contentHash: String
    let documentRevision: Int64
    let vectorPayload: [Float]
    let embeddingBindingId: String?
}
