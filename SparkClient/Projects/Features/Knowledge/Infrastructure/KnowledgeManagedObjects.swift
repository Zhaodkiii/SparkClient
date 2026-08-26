import CoreData
import Foundation

/// Manual Core Data declarations keep knowledge entities usable on background contexts when
/// the application target defaults otherwise-unannotated declarations to `MainActor`.
@objc(KnowledgeDocumentEntity)
nonisolated final class KnowledgeDocumentEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<KnowledgeDocumentEntity> {
        NSFetchRequest<KnowledgeDocumentEntity>(entityName: "KnowledgeDocumentEntity")
    }

    @NSManaged var boundModelID: String?
    @NSManaged var chunkCount: Int32
    @NSManaged var content: String?
    @NSManaged var contentHash: String?
    @NSManaged var createdAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var excerpt: String?
    @NSManaged var id: UUID?
    @NSManaged var isEmbeddingIndexed: Bool
    @NSManaged var isRemoteDeleted: Bool
    @NSManaged var knowledgeBaseID: UUID?
    @NSManaged var lastEmbeddingModelName: String?
    @NSManaged var lastSyncAttemptAt: Date?
    @NSManaged var lastSyncErrorCode: String?
    @NSManaged var lastSyncStateRaw: String?
    @NSManaged var lastSyncSucceededAt: Date?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var scopeRaw: String?
    @NSManaged var serverRevision: Int64
    @NSManaged var serverUpdatedAt: Date?
    @NSManaged var sourceRaw: String?
    @NSManaged var title: String?
    @NSManaged var updatedAt: Date?
}

nonisolated extension KnowledgeDocumentEntity: Identifiable {}

@objc(KnowledgeChunkEntity)
nonisolated final class KnowledgeChunkEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<KnowledgeChunkEntity> {
        NSFetchRequest<KnowledgeChunkEntity>(entityName: "KnowledgeChunkEntity")
    }

    @NSManaged var content: String?
    @NSManaged var createdAt: Date?
    @NSManaged var documentID: UUID?
    @NSManaged var id: UUID?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var sequence: Int32
    @NSManaged var updatedAt: Date?
    @NSManaged var vectorData: Data?
}

nonisolated extension KnowledgeChunkEntity: Identifiable {}

/// 知识同步待发队列：与 `KnowledgeDocumentEntity` 的写入处于同一 Core Data 事务，
/// 保证“本地事实 + Outbox 入队”不可分割（工单 5.2）。
@objc(KnowledgeSyncOutboxEntity)
nonisolated final class KnowledgeSyncOutboxEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<KnowledgeSyncOutboxEntity> {
        NSFetchRequest<KnowledgeSyncOutboxEntity>(entityName: "KnowledgeSyncOutboxEntity")
    }

    @NSManaged var attemptCount: Int32
    @NSManaged var baseRevision: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var documentID: UUID?
    @NSManaged var lastErrorCode: String?
    @NSManaged var mutationID: UUID?
    @NSManaged var nextAttemptAt: Date?
    @NSManaged var operationRaw: String?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var payloadData: Data?
    @NSManaged var requestHash: String?
    @NSManaged var stateRaw: String?
    @NSManaged var updatedAt: Date?
}

nonisolated extension KnowledgeSyncOutboxEntity: Identifiable {}
