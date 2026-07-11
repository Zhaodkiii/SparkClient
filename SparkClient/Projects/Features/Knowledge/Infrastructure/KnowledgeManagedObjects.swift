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
    @NSManaged var createdAt: Date?
    @NSManaged var excerpt: String?
    @NSManaged var id: UUID?
    @NSManaged var isEmbeddingIndexed: Bool
    @NSManaged var lastEmbeddingModelName: String?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var scopeRaw: String?
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
