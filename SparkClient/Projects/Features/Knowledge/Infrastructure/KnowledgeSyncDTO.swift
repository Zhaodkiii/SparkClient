import Foundation

// MARK: - 服务端知识文档 DTO（对齐 SparkService `chat_sync.ai_knowledge` 的统一 document payload）

struct KnowledgeRemoteDocumentDTO: Codable, Sendable {
    let id: UUID
    let knowledgeBaseId: UUID?
    let title: String
    let content: String
    let excerpt: String
    let scope: String
    let boundModelId: String?
    let source: String
    let revision: Int64
    let contentHash: String
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date?
    let serverUpdatedAt: Date
}

// MARK: - 默认知识库 DTO

struct KnowledgeDefaultBaseDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let kind: String
    let isDefault: Bool
    let revision: Int64
    let serverUpdatedAt: Date
}

// MARK: - Push 请求/响应 DTO

struct KnowledgeMutationDocumentDTO: Codable, Sendable {
    let title: String
    let content: String
    let excerpt: String
    let scope: String
    let boundModelId: String?
    let source: String
    let clientCreatedAt: Date?
    let clientUpdatedAt: Date?
}

struct KnowledgeMutationClientDTO: Codable, Sendable {
    let platform: String
    let version: String
    let deviceId: String?
}

struct KnowledgeMutationRequestDTO: Codable, Sendable {
    let mutationId: UUID
    let documentId: UUID
    let operation: String
    let baseRevision: Int64?
    let knowledgeBaseId: UUID?
    let document: KnowledgeMutationDocumentDTO?
    let client: KnowledgeMutationClientDTO?
}

struct KnowledgePushAckDTO: Codable, Sendable {
    let mutationId: UUID
    let documentId: String?
    let status: String
    let replayed: Bool?
    let revision: Int64?
    let serverUpdatedAt: Date?
    let contentHash: String?
    let code: String?
    let currentDocument: KnowledgeRemoteDocumentDTO?
}

struct KnowledgePushResponseDTO: Decodable, Sendable {
    let results: [KnowledgePushAckDTO]
}

// MARK: - Pull 响应 DTO

struct KnowledgePullResponseDTO: Decodable, Sendable {
    let cursor: String?
    let hasMore: Bool?
    let documents: [KnowledgeRemoteDocumentDTO]
}

// MARK: - 本地 Outbox 冻结快照（不经网络传输，只用于 `KnowledgeSyncOutboxEntity.payloadData`）
//
// create/update 携带完整字段；delete/restore 不需要文档正文，保持字段皆为 nil。
nonisolated struct KnowledgeOutboxPayload: Codable, Sendable, Equatable {
    var knowledgeBaseID: UUID?
    var title: String?
    var content: String?
    var excerpt: String?
    var scope: KnowledgeDocumentScope?
    var boundModelID: String?
    var source: KnowledgeDocumentSource?
    var clientCreatedAt: Date?
    var clientUpdatedAt: Date?

    nonisolated static let empty = KnowledgeOutboxPayload()

    nonisolated func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    nonisolated static func decode(_ data: Data) -> KnowledgeOutboxPayload {
        (try? JSONDecoder().decode(KnowledgeOutboxPayload.self, from: data)) ?? .empty
    }
}
