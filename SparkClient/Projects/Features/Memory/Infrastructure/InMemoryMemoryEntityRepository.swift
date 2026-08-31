import Foundation

nonisolated final class InMemoryMemoryEntityRepository: MemoryEntityRepository, @unchecked Sendable {
    private var entries: [MemoryEntry] = []
    private var outbox: [MemoryOutboxRecord] = []
    private var cursor: String?

    func listArchiveEntries(query: String?) async throws -> [MemoryEntry] {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let visible = entries.filter { $0.isDeleted == false }
        guard trimmed.isEmpty == false else { return visible }
        return visible.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.content.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func createArchiveEntry(title: String, content: String, pinned: Bool) async throws -> MemoryEntry {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw MemoryRepositoryError.emptyContent }
        let now = Date()
        let entry = MemoryEntry(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(trimmed.prefix(20)) : title,
            content: String(trimmed.prefix(240)),
            isPinned: pinned,
            scope: "account",
            scopeKey: "account",
            layer: "L3",
            documentKey: "preferences",
            sectionKey: "answer_style",
            memoryType: "preference",
            revision: 0,
            status: "active",
            confirmationStatus: "not_required",
            sensitivity: "normal",
            source: "user",
            isDeleted: false,
            createdAt: now,
            updatedAt: now,
            serverUpdatedAt: nil,
            expiresAt: nil,
            syncState: .pending,
            lastSyncErrorCode: nil
        )
        entries.append(entry)
        return entry
    }

    func updateArchiveEntry(id: UUID, title: String, content: String, pinned: Bool) async throws -> MemoryEntry {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw MemoryRepositoryError.emptyContent }
        guard let index = entries.firstIndex(where: { $0.id == id && $0.isDeleted == false }) else {
            throw MemoryRepositoryError.notFound
        }
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(trimmed.prefix(20))
            : title
        entries[index].title = resolvedTitle
        entries[index].content = String(trimmed.prefix(240))
        entries[index].isPinned = pinned
        entries[index].updatedAt = Date()
        return entries[index]
    }

    func deleteArchiveEntry(id: UUID) async throws {
        entries.removeAll { $0.id == id }
    }

    func deleteAllArchiveEntries() async throws {
        entries.removeAll()
    }

    func loadPendingOutbox(limit: Int) async -> [MemoryOutboxRecord] { Array(outbox.prefix(limit)) }
    func recoverSendingOutboxToPending() async {}
    func discardOutboxCoveredByHigherRevision() async {}
    func markOutboxSending(mutationIDs: [UUID]) async {}
    func markOutboxAccepted(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {}
    func resolveConflictWithServerSnapshot(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {}
    func markOutboxFailedRetryable(mutationID: UUID, errorCode: String, nextRetryAt: Date) async {}
    func markOutboxFailedPermanent(mutationID: UUID, errorCode: String) async {}
    func applyRemoteSnapshots(_ snapshots: [MemoryRemoteSnapshot]) async {}
    func loadSyncCursor() async -> String? { cursor }
    func saveSyncCursor(_ value: String?, pullSucceeded: Bool, errorCode: String?) async { cursor = value }
    func markPullStarted() async {}
}
