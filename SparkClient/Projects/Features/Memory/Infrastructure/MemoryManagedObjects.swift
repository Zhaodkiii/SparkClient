import CoreData
import Foundation

/// Manual Core Data declarations keep memory sync entities usable on background contexts.
@objc(MemoryEntity)
nonisolated final class MemoryEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MemoryEntity> {
        NSFetchRequest<MemoryEntity>(entityName: "MemoryEntity")
    }

    @NSManaged var agentKey: String?
    @NSManaged var confirmationStatus: String?
    @NSManaged var content: String?
    @NSManaged var createdAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var documentKey: String?
    @NSManaged var expiresAt: Date?
    @NSManaged var id: UUID?
    @NSManaged var isPinned: Bool
    @NSManaged var isRemoteDeleted: Bool
    @NSManaged var lastSyncedRevision: Int64
    @NSManaged var lastSyncAttemptAt: Date?
    @NSManaged var lastSyncErrorAt: Date?
    @NSManaged var lastSyncErrorCode: String?
    @NSManaged var lastSyncSucceededAt: Date?
    @NSManaged var layer: String?
    @NSManaged var memberID: Int64
    @NSManaged var memoryType: String?
    @NSManaged var normalizedKey: String?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var revision: Int64
    @NSManaged var scope: String?
    @NSManaged var scopeKey: String?
    @NSManaged var sectionKey: String?
    @NSManaged var sensitivity: String?
    @NSManaged var serverSnapshotHash: String?
    @NSManaged var serverUpdatedAt: Date?
    @NSManaged var sortOrder: Int32
    @NSManaged var source: String?
    @NSManaged var status: String?
    @NSManaged var structuredValueData: Data?
    @NSManaged var syncStateRaw: String?
    @NSManaged var threadID: UUID?
    @NSManaged var title: String?
    @NSManaged var updatedAt: Date?
}

nonisolated extension MemoryEntity: Identifiable {}

@objc(MemorySyncOutboxEntity)
nonisolated final class MemorySyncOutboxEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MemorySyncOutboxEntity> {
        NSFetchRequest<MemorySyncOutboxEntity>(entityName: "MemorySyncOutboxEntity")
    }

    @NSManaged var attemptCount: Int32
    @NSManaged var baseRevision: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var id: UUID?
    @NSManaged var lastErrorAt: Date?
    @NSManaged var lastErrorCode: String?
    @NSManaged var memoryID: UUID?
    @NSManaged var mutationID: UUID?
    @NSManaged var nextRetryAt: Date?
    @NSManaged var operationRaw: String?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var payloadData: Data?
    @NSManaged var payloadHash: String?
    @NSManaged var stateRaw: String?
    @NSManaged var updatedAt: Date?
}

nonisolated extension MemorySyncOutboxEntity: Identifiable {}

@objc(MemorySyncCursorEntity)
nonisolated final class MemorySyncCursorEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MemorySyncCursorEntity> {
        NSFetchRequest<MemorySyncCursorEntity>(entityName: "MemorySyncCursorEntity")
    }

    @NSManaged var cursor: String?
    @NSManaged var lastPullErrorCode: String?
    @NSManaged var lastPullStartedAt: Date?
    @NSManaged var lastPullSucceededAt: Date?
    @NSManaged var ownerAccountID: Int64
    @NSManaged var schemaVersion: Int32
    @NSManaged var updatedAt: Date?
}

@objc(MemorySettingsEntity)
nonisolated final class MemorySettingsEntity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MemorySettingsEntity> {
        NSFetchRequest<MemorySettingsEntity>(entityName: "MemorySettingsEntity")
    }

    @NSManaged var allowCrossThreadRecall: Bool
    @NSManaged var allowSensitiveSources: Bool
    @NSManaged var allowToolWrite: Bool
    @NSManaged var autoConsolidationEnabled: Bool
    @NSManaged var isEnabled: Bool
    @NSManaged var maxRecallCount: Int32
    @NSManaged var ownerAccountID: Int64
    @NSManaged var revision: Int64
    @NSManaged var serverUpdatedAt: Date?
    @NSManaged var syncStateRaw: String?
    @NSManaged var updatedAt: Date?
}
