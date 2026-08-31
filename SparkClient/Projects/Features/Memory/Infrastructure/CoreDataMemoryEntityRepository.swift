import CoreData
import CryptoKit
import Foundation

nonisolated final class CoreDataMemoryEntityRepository: MemoryEntityRepository, @unchecked Sendable {
    private let coreDataStack: CoreDataStack
    private let snapshotStore: SessionSnapshotStore

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger _: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.snapshotStore = snapshotStore
    }

    func listArchiveEntries(query: String?) async throws -> [MemoryEntry] {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            let request = MemoryEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false),
            ]
            var predicates = [
                self.ownerPredicate(accountID),
                NSPredicate(format: "isRemoteDeleted == NO"),
                NSPredicate(format: "layer == %@", "L3"),
                NSPredicate(format: "documentKey == %@", "preferences"),
            ]
            if let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false {
                predicates.append(NSPredicate(
                    format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@",
                    trimmed,
                    trimmed
                ))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return try context.fetch(request).compactMap { $0.toDomain() }
        }
    }

    func createArchiveEntry(title: String, content: String, pinned: Bool) async throws -> MemoryEntry {
        let accountID = try await requireAccountID()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw MemoryRepositoryError.emptyContent }
        let clamped = String(trimmed.prefix(240))
        let resolvedTitle = {
            let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? String(clamped.prefix(20)) : String(value.prefix(128))
        }()
        let entry = try await coreDataStack.performBackgroundTask { context in
            let now = Date()
            let entity = MemoryEntity(context: context)
            entity.id = UUID()
            entity.ownerAccountID = accountID
            entity.scope = "account"
            entity.scopeKey = "account"
            entity.layer = "L3"
            entity.documentKey = "preferences"
            entity.sectionKey = "answer_style"
            entity.memoryType = "preference"
            entity.normalizedKey = ""
            entity.title = resolvedTitle
            entity.content = clamped
            entity.isPinned = pinned
            entity.sortOrder = 0
            entity.source = "user"
            entity.confirmationStatus = "not_required"
            entity.sensitivity = "normal"
            entity.status = "active"
            entity.revision = 0
            entity.lastSyncedRevision = 0
            entity.isRemoteDeleted = false
            entity.createdAt = now
            entity.updatedAt = now
            entity.syncStateRaw = MemorySyncState.pending.rawValue
            let payload = self.makeOutboxPayload(for: entity)
            _ = try self.upsertOutboxRow(
                memoryID: entity.id!,
                ownerAccountID: accountID,
                intent: .create,
                knownServerRevision: 0,
                payload: payload,
                context: context
            )
            guard let domain = entity.toDomain() else {
                throw self.memoryError("记忆创建后无法生成领域对象")
            }
            return domain
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
        NotificationCenter.default.post(name: .sparkMemoryLocalMutationDidHappen, object: nil)
        return entry
    }

    func updateArchiveEntry(id: UUID, title: String, content: String, pinned: Bool) async throws -> MemoryEntry {
        let accountID = try await requireAccountID()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw MemoryRepositoryError.emptyContent }
        let clamped = String(trimmed.prefix(240))
        let resolvedTitle = {
            let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? String(clamped.prefix(20)) : String(value.prefix(128))
        }()
        let entry = try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchMemory(id: id, ownerAccountID: accountID, context: context, includeDeleted: false) else {
                throw MemoryRepositoryError.notFound
            }
            entity.title = resolvedTitle
            entity.content = clamped
            entity.isPinned = pinned
            entity.updatedAt = Date()
            let payload = self.makeOutboxPayload(for: entity)
            let stillNeedsNetwork = try self.upsertOutboxRow(
                memoryID: id,
                ownerAccountID: accountID,
                intent: .update,
                knownServerRevision: entity.revision,
                payload: payload,
                context: context
            )
            entity.syncStateRaw = stillNeedsNetwork ? MemorySyncState.pending.rawValue : entity.syncStateRaw
            guard let domain = entity.toDomain() else {
                throw self.memoryError("记忆更新后无法生成领域对象")
            }
            return domain
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
        NotificationCenter.default.post(name: .sparkMemoryLocalMutationDidHappen, object: nil)
        return entry
    }

    func deleteArchiveEntry(id: UUID) async throws {
        let accountID = try await requireAccountID()
        try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchMemory(id: id, ownerAccountID: accountID, context: context, includeDeleted: true) else {
                return
            }
            let stillNeedsNetwork = try self.upsertOutboxRow(
                memoryID: id,
                ownerAccountID: accountID,
                intent: .delete,
                knownServerRevision: entity.revision,
                payload: .empty,
                context: context
            )
            entity.isRemoteDeleted = true
            entity.deletedAt = Date()
            entity.updatedAt = Date()
            entity.syncStateRaw = stillNeedsNetwork ? MemorySyncState.pending.rawValue : MemorySyncState.synced.rawValue
            if stillNeedsNetwork == false {
                context.delete(entity)
            }
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
        NotificationCenter.default.post(name: .sparkMemoryLocalMutationDidHappen, object: nil)
    }

    func deleteAllArchiveEntries() async throws {
        let entries = try await listArchiveEntries(query: nil)
        for entry in entries {
            try await deleteArchiveEntry(id: entry.id)
        }
    }

    func loadPendingOutbox(limit: Int) async -> [MemoryOutboxRecord] {
        guard let accountID = try? await requireAccountID() else { return [] }
        return (try? await coreDataStack.performBackgroundTask { context in
            let request = MemorySyncOutboxEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.fetchLimit = max(limit, 1)
            let now = Date()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "stateRaw == %@", MemoryOutboxState.pending.rawValue),
                    NSPredicate(format: "stateRaw == %@", MemoryOutboxState.sending.rawValue),
                    NSCompoundPredicate(andPredicateWithSubpredicates: [
                        NSPredicate(format: "stateRaw == %@", MemoryOutboxState.retryableFailed.rawValue),
                        NSCompoundPredicate(orPredicateWithSubpredicates: [
                            NSPredicate(format: "nextRetryAt == nil"),
                            NSPredicate(format: "nextRetryAt <= %@", now as NSDate),
                        ]),
                    ]),
                ]),
            ])
            return try context.fetch(request).compactMap { $0.toRecord() }
        }) ?? []
    }

    func recoverSendingOutboxToPending() async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = MemorySyncOutboxEntity.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSPredicate(format: "stateRaw == %@", MemoryOutboxState.sending.rawValue),
            ])
            for row in try context.fetch(request) {
                row.stateRaw = MemoryOutboxState.pending.rawValue
                row.updatedAt = Date()
                if let memoryID = row.memoryID,
                   let entity = try self.fetchMemory(id: memoryID, ownerAccountID: accountID, context: context, includeDeleted: true) {
                    entity.syncStateRaw = MemorySyncState.pending.rawValue
                }
            }
        }
    }

    func discardOutboxCoveredByHigherRevision() async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = MemorySyncOutboxEntity.fetchRequest()
            request.predicate = self.ownerPredicate(accountID)
            for row in try context.fetch(request) {
                guard let memoryID = row.memoryID else { continue }
                guard let entity = try self.fetchMemory(id: memoryID, ownerAccountID: accountID, context: context, includeDeleted: true) else {
                    continue
                }
                if entity.revision > row.baseRevision {
                    context.delete(row)
                    entity.syncStateRaw = MemorySyncState.resolvedByServer.rawValue
                    entity.lastSyncSucceededAt = Date()
                    entity.lastSyncErrorCode = nil
                }
            }
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func markOutboxSending(mutationIDs: [UUID]) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = MemorySyncOutboxEntity.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSPredicate(format: "mutationID IN %@", mutationIDs),
            ])
            for row in try context.fetch(request) {
                row.stateRaw = MemoryOutboxState.sending.rawValue
                row.updatedAt = Date()
                if let memoryID = row.memoryID,
                   let entity = try self.fetchMemory(id: memoryID, ownerAccountID: accountID, context: context, includeDeleted: true) {
                    entity.syncStateRaw = MemorySyncState.syncing.rawValue
                    entity.lastSyncAttemptAt = Date()
                }
            }
        }
    }

    func markOutboxAccepted(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            try self.removeOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context)
            try self.applySnapshot(snapshot, ownerAccountID: accountID, context: context, resultingState: .synced)
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func resolveConflictWithServerSnapshot(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            try self.removeOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context)
            try self.applySnapshot(snapshot, ownerAccountID: accountID, context: context, resultingState: .resolvedByServer)
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func markOutboxFailedRetryable(mutationID: UUID, errorCode: String, nextRetryAt: Date) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let row = try self.fetchOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context) else { return }
            row.stateRaw = MemoryOutboxState.retryableFailed.rawValue
            row.attemptCount += 1
            row.lastErrorCode = errorCode
            row.lastErrorAt = Date()
            row.nextRetryAt = nextRetryAt
            row.updatedAt = Date()
            if let memoryID = row.memoryID,
               let entity = try self.fetchMemory(id: memoryID, ownerAccountID: accountID, context: context, includeDeleted: true) {
                entity.syncStateRaw = MemorySyncState.failedRetryable.rawValue
                entity.lastSyncAttemptAt = Date()
                entity.lastSyncErrorCode = errorCode
                entity.lastSyncErrorAt = Date()
            }
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func markOutboxFailedPermanent(mutationID: UUID, errorCode: String) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let row = try self.fetchOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context) else { return }
            row.stateRaw = MemoryOutboxState.permanentFailed.rawValue
            row.lastErrorCode = errorCode
            row.lastErrorAt = Date()
            row.updatedAt = Date()
            if let memoryID = row.memoryID,
               let entity = try self.fetchMemory(id: memoryID, ownerAccountID: accountID, context: context, includeDeleted: true) {
                entity.syncStateRaw = MemorySyncState.failedPermanent.rawValue
                entity.lastSyncAttemptAt = Date()
                entity.lastSyncErrorCode = errorCode
                entity.lastSyncErrorAt = Date()
            }
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func applyRemoteSnapshots(_ snapshots: [MemoryRemoteSnapshot]) async {
        guard snapshots.isEmpty == false else { return }
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let active = Set(try context.fetch(self.allOutboxRequest(ownerAccountID: accountID)).compactMap(\.memoryID))
            for snapshot in snapshots {
                if let existing = try self.fetchMemory(id: snapshot.id, ownerAccountID: accountID, context: context, includeDeleted: true),
                   existing.syncStateRaw == MemorySyncState.localOnly.rawValue {
                    continue
                }
                if active.contains(snapshot.id), snapshot.revision == 0 {
                    continue
                }
                if active.contains(snapshot.id) {
                    if let row = try self.fetchOutboxRow(memoryID: snapshot.id, ownerAccountID: accountID, context: context),
                       snapshot.revision <= row.baseRevision {
                        continue
                    }
                }
                try self.applySnapshot(snapshot, ownerAccountID: accountID, context: context, resultingState: .synced)
            }
        }
        NotificationCenter.default.post(name: .sparkMemoryDatabaseDidChange, object: nil)
    }

    func loadSyncCursor() async -> String? {
        guard let accountID = try? await requireAccountID() else { return nil }
        return try? await coreDataStack.performBackgroundTask { context in
            try self.fetchCursor(ownerAccountID: accountID, context: context)?.cursor
        }
    }

    func saveSyncCursor(_ value: String?, pullSucceeded: Bool, errorCode: String?) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let entity = try self.fetchCursor(ownerAccountID: accountID, context: context)
                ?? MemorySyncCursorEntity(context: context)
            entity.ownerAccountID = accountID
            if let value {
                entity.cursor = value
            }
            entity.schemaVersion = 1
            entity.updatedAt = Date()
            if pullSucceeded {
                entity.lastPullSucceededAt = Date()
                entity.lastPullErrorCode = nil
            } else {
                entity.lastPullErrorCode = errorCode
            }
        }
    }

    func markPullStarted() async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let entity = try self.fetchCursor(ownerAccountID: accountID, context: context)
                ?? MemorySyncCursorEntity(context: context)
            entity.ownerAccountID = accountID
            entity.lastPullStartedAt = Date()
            entity.schemaVersion = 1
            entity.updatedAt = Date()
        }
    }

    private func makeOutboxPayload(for entity: MemoryEntity) -> MemoryOutboxPayload {
        MemoryOutboxPayload(
            scope: entity.scope ?? "account",
            layer: entity.layer ?? "L3",
            documentKey: entity.documentKey ?? "preferences",
            sectionKey: entity.sectionKey ?? "answer_style",
            memoryType: entity.memoryType ?? "preference",
            title: entity.title ?? "",
            content: entity.content ?? "",
            isPinned: entity.isPinned,
            source: entity.source ?? "user",
            sensitivity: entity.sensitivity ?? "normal"
        )
    }

    @discardableResult
    private func upsertOutboxRow(
        memoryID: UUID,
        ownerAccountID: Int64,
        intent: MemorySyncOperation,
        knownServerRevision: Int64,
        payload: MemoryOutboxPayload,
        context: NSManagedObjectContext
    ) throws -> Bool {
        guard let existing = try fetchOutboxRow(memoryID: memoryID, ownerAccountID: ownerAccountID, context: context) else {
            if knownServerRevision == 0 {
                if intent == .delete { return false }
                return try insertOutboxRow(
                    memoryID: memoryID,
                    ownerAccountID: ownerAccountID,
                    operation: .create,
                    baseRevision: 0,
                    payload: payload,
                    context: context
                )
            }
            return try insertOutboxRow(
                memoryID: memoryID,
                ownerAccountID: ownerAccountID,
                operation: intent,
                baseRevision: knownServerRevision,
                payload: payload,
                context: context
            )
        }
        let current = MemorySyncOperation(rawValue: existing.operationRaw ?? "") ?? .update
        switch (current, intent) {
        case (.create, .delete):
            context.delete(existing)
            return false
        case (.create, _):
            existing.payloadData = payload.encoded()
            existing.payloadHash = Self.hash(payload.encoded())
        case (.update, .delete):
            existing.operationRaw = MemorySyncOperation.delete.rawValue
            existing.payloadData = MemoryOutboxPayload.empty.encoded()
            existing.payloadHash = Self.hash(existing.payloadData ?? Data())
        case (.update, _):
            existing.payloadData = payload.encoded()
            existing.payloadHash = Self.hash(payload.encoded())
        case (.delete, .delete):
            break
        case (.delete, _):
            break
        default:
            existing.payloadData = payload.encoded()
            existing.payloadHash = Self.hash(payload.encoded())
        }
        existing.stateRaw = MemoryOutboxState.pending.rawValue
        existing.lastErrorCode = nil
        existing.updatedAt = Date()
        return true
    }

    private func insertOutboxRow(
        memoryID: UUID,
        ownerAccountID: Int64,
        operation: MemorySyncOperation,
        baseRevision: Int64,
        payload: MemoryOutboxPayload,
        context: NSManagedObjectContext
    ) throws -> Bool {
        let row = MemorySyncOutboxEntity(context: context)
        let data = payload.encoded()
        row.id = UUID()
        row.mutationID = UUID()
        row.ownerAccountID = ownerAccountID
        row.memoryID = memoryID
        row.operationRaw = operation.rawValue
        row.baseRevision = baseRevision
        row.payloadData = data
        row.payloadHash = Self.hash(data)
        row.stateRaw = MemoryOutboxState.pending.rawValue
        row.attemptCount = 0
        let now = Date()
        row.createdAt = now
        row.updatedAt = now
        return true
    }

    private func applySnapshot(
        _ snapshot: MemoryRemoteSnapshot,
        ownerAccountID: Int64,
        context: NSManagedObjectContext,
        resultingState: MemorySyncState
    ) throws {
        let entity = try fetchMemory(id: snapshot.id, ownerAccountID: ownerAccountID, context: context, includeDeleted: true)
            ?? MemoryEntity(context: context)
        if entity.id == nil {
            entity.id = snapshot.id
            entity.ownerAccountID = ownerAccountID
            entity.createdAt = snapshot.createdAt ?? snapshot.serverUpdatedAt
        }
        entity.scope = snapshot.scope
        entity.scopeKey = snapshot.scopeKey
        entity.memberID = snapshot.memberID ?? 0
        entity.agentKey = snapshot.agentKey
        entity.threadID = snapshot.threadID
        entity.layer = snapshot.layer
        entity.documentKey = snapshot.documentKey
        entity.sectionKey = snapshot.sectionKey
        entity.memoryType = snapshot.memoryType
        entity.normalizedKey = snapshot.normalizedKey
        entity.title = snapshot.title
        entity.content = snapshot.content
        entity.structuredValueData = snapshot.structuredValueData
        entity.isPinned = snapshot.isPinned
        entity.sortOrder = snapshot.sortOrder
        entity.source = snapshot.source
        entity.confirmationStatus = snapshot.confirmationStatus
        entity.sensitivity = snapshot.sensitivity
        entity.status = snapshot.status
        entity.expiresAt = snapshot.expiresAt
        entity.revision = snapshot.revision
        entity.lastSyncedRevision = snapshot.revision
        entity.isRemoteDeleted = snapshot.isDeleted
        entity.deletedAt = snapshot.deletedAt
        entity.serverUpdatedAt = snapshot.serverUpdatedAt
        entity.serverSnapshotHash = snapshot.contentHash
        entity.updatedAt = snapshot.serverUpdatedAt
        entity.syncStateRaw = resultingState.rawValue
        entity.lastSyncSucceededAt = Date()
        entity.lastSyncErrorCode = nil
        entity.lastSyncErrorAt = nil
    }

    private func fetchMemory(
        id: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext,
        includeDeleted: Bool
    ) throws -> MemoryEntity? {
        let request = MemoryEntity.fetchRequest()
        request.fetchLimit = 1
        var predicates = [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "id == %@", id as CVarArg),
        ]
        if includeDeleted == false {
            predicates.append(NSPredicate(format: "isRemoteDeleted == NO"))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.fetch(request).first
    }

    private func fetchOutboxRow(
        memoryID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> MemorySyncOutboxEntity? {
        let request = MemorySyncOutboxEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "memoryID == %@", memoryID as CVarArg),
            NSPredicate(format: "stateRaw IN %@", [
                MemoryOutboxState.pending.rawValue,
                MemoryOutboxState.sending.rawValue,
                MemoryOutboxState.retryableFailed.rawValue,
            ]),
        ])
        return try context.fetch(request).first
    }

    private func fetchOutboxRow(
        mutationID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> MemorySyncOutboxEntity? {
        let request = MemorySyncOutboxEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "mutationID == %@", mutationID as CVarArg),
        ])
        return try context.fetch(request).first
    }

    private func removeOutboxRow(mutationID: UUID, ownerAccountID: Int64, context: NSManagedObjectContext) throws {
        if let row = try fetchOutboxRow(mutationID: mutationID, ownerAccountID: ownerAccountID, context: context) {
            context.delete(row)
        }
    }

    private func allOutboxRequest(ownerAccountID: Int64) -> NSFetchRequest<MemorySyncOutboxEntity> {
        let request = MemorySyncOutboxEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "stateRaw IN %@", [
                MemoryOutboxState.pending.rawValue,
                MemoryOutboxState.sending.rawValue,
                MemoryOutboxState.retryableFailed.rawValue,
            ]),
        ])
        return request
    }

    private func fetchCursor(ownerAccountID: Int64, context: NSManagedObjectContext) throws -> MemorySyncCursorEntity? {
        let request = MemorySyncCursorEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = ownerPredicate(ownerAccountID)
        return try context.fetch(request).first
    }

    private func ownerPredicate(_ ownerAccountID: Int64) -> NSPredicate {
        NSPredicate(format: "ownerAccountID == %lld", ownerAccountID)
    }

    private func requireAccountID() async throws -> Int64 {
        if let accountID = await snapshotStore.load()?.accountID {
            return accountID
        }
        throw MemoryRepositoryError.notSignedIn
    }

    private func memoryError(_ description: String) -> NSError {
        NSError(domain: "SparkMemory", code: -1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated private extension MemoryEntity {
    nonisolated func toDomain() -> MemoryEntry? {
        guard let id, let createdAt, let updatedAt else { return nil }
        return MemoryEntry(
            id: id,
            title: title ?? "",
            content: content ?? "",
            isPinned: isPinned,
            scope: scope ?? "account",
            scopeKey: scopeKey ?? "account",
            layer: layer ?? "L3",
            documentKey: documentKey ?? "preferences",
            sectionKey: sectionKey ?? "answer_style",
            memoryType: memoryType ?? "preference",
            revision: revision,
            status: status ?? "active",
            confirmationStatus: confirmationStatus ?? "not_required",
            sensitivity: sensitivity ?? "normal",
            source: source ?? "user",
            isDeleted: self.isRemoteDeleted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            serverUpdatedAt: serverUpdatedAt,
            expiresAt: expiresAt,
            syncState: MemorySyncState(rawValue: syncStateRaw ?? "") ?? .localOnly,
            lastSyncErrorCode: lastSyncErrorCode
        )
    }
}

nonisolated private extension MemorySyncOutboxEntity {
    nonisolated func toRecord() -> MemoryOutboxRecord? {
        guard let mutationID, let memoryID, let operationRaw, let operation = MemorySyncOperation(rawValue: operationRaw) else {
            return nil
        }
        return MemoryOutboxRecord(
            mutationID: mutationID,
            memoryID: memoryID,
            operation: operation,
            baseRevision: baseRevision,
            payload: payloadData ?? Data(),
            payloadHash: payloadHash ?? "",
            attemptCount: attemptCount,
            nextRetryAt: nextRetryAt
        )
    }
}
