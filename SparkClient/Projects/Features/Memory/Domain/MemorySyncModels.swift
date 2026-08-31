import Foundation

/// 服务端权威记忆条目在客户端的领域投影（新同步体系，不替代旧 `MemoryRecord`）。
nonisolated enum MemorySyncState: String, Codable, CaseIterable, Sendable {
    case localOnly = "local_only"
    case pending
    case syncing
    case synced
    case failedRetryable = "failed_retryable"
    case failedPermanent = "failed_permanent"
    case resolvedByServer = "resolved_by_server"

    var badgeTitle: String {
        switch self {
        case .localOnly, .synced:
            return ""
        case .pending, .syncing:
            return "同步中"
        case .failedRetryable:
            return "同步失败，可重试"
        case .failedPermanent:
            return "同步失败"
        case .resolvedByServer:
            return "已按云端版本更新"
        }
    }

    var isRetryable: Bool {
        self == .failedRetryable
    }
}

nonisolated enum MemorySyncOperation: String, Codable, CaseIterable, Sendable {
    case create
    case update
    case confirm
    case reject
    case delete
}

nonisolated enum MemoryOutboxState: String, Codable, CaseIterable, Sendable {
    case pending
    case sending
    case acknowledged
    case retryableFailed = "retryable_failed"
    case permanentFailed = "permanent_failed"
    case discarded
}

nonisolated struct MemoryEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var isPinned: Bool
    var scope: String
    var scopeKey: String
    var layer: String
    var documentKey: String
    var sectionKey: String
    var memoryType: String
    var revision: Int64
    var status: String
    var confirmationStatus: String
    var sensitivity: String
    var source: String
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var serverUpdatedAt: Date?
    var expiresAt: Date?
    var syncState: MemorySyncState
    var lastSyncErrorCode: String?

    var pinned: Bool { isPinned }

    func asRecord() -> MemoryRecord {
        MemoryRecord(
            id: id,
            title: title,
            content: content,
            pinned: isPinned,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated struct MemoryOutboxRecord: Identifiable, Equatable, Sendable {
    let mutationID: UUID
    let memoryID: UUID
    let operation: MemorySyncOperation
    let baseRevision: Int64
    let payload: Data
    let payloadHash: String
    let attemptCount: Int32
    let nextRetryAt: Date?

    var id: UUID { mutationID }
}

nonisolated struct MemoryRemoteSnapshot: Equatable, Sendable {
    let id: UUID
    let scope: String
    let scopeKey: String
    let memberID: Int64?
    let agentKey: String?
    let threadID: UUID?
    let layer: String
    let documentKey: String
    let sectionKey: String
    let memoryType: String
    let normalizedKey: String
    let title: String
    let content: String
    let structuredValueData: Data?
    let isPinned: Bool
    let sortOrder: Int32
    let source: String
    let confirmationStatus: String
    let sensitivity: String
    let status: String
    let expiresAt: Date?
    let contentHash: String
    let revision: Int64
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date?
    let serverUpdatedAt: Date
}

nonisolated protocol MemoryEntityRepository: Sendable {
    func listArchiveEntries(query: String?) async throws -> [MemoryEntry]
    func createArchiveEntry(title: String, content: String, pinned: Bool) async throws -> MemoryEntry
    func updateArchiveEntry(id: UUID, title: String, content: String, pinned: Bool) async throws -> MemoryEntry
    func deleteArchiveEntry(id: UUID) async throws
    func deleteAllArchiveEntries() async throws

    func loadPendingOutbox(limit: Int) async -> [MemoryOutboxRecord]
    func recoverSendingOutboxToPending() async
    func discardOutboxCoveredByHigherRevision() async
    func markOutboxSending(mutationIDs: [UUID]) async
    func markOutboxAccepted(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async
    func resolveConflictWithServerSnapshot(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async
    func markOutboxFailedRetryable(mutationID: UUID, errorCode: String, nextRetryAt: Date) async
    func markOutboxFailedPermanent(mutationID: UUID, errorCode: String) async

    func applyRemoteSnapshots(_ snapshots: [MemoryRemoteSnapshot]) async
    func loadSyncCursor() async -> String?
    func saveSyncCursor(_ value: String?, pullSucceeded: Bool, errorCode: String?) async
    func markPullStarted() async
}
