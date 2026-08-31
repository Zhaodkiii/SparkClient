import Foundation

/// Chat tools and the memory archive share this store: writes go to the synced
/// archive, while retrieve still includes older local-only rows.
nonisolated final class ToolingMemoryRepository: MemoryRepository, @unchecked Sendable {
    private let local: any MemoryRepository
    private let synced: any MemoryEntityRepository
    private let searchEngine = MemorySearchEngine()

    init(local: any MemoryRepository, synced: any MemoryEntityRepository) {
        self.local = local
        self.synced = synced
    }

    func loadPreferences() async -> MemoryPreferences {
        await local.loadPreferences()
    }

    func savePreferences(_ preferences: MemoryPreferences) async throws {
        try await local.savePreferences(preferences)
    }

    func list(query: String?) async throws -> [MemoryRecord] {
        try await mergedRecords(query: query)
    }

    func save(title: String?, content: String, pinned: Bool) async throws -> MemoryRecord {
        let entry = try await synced.createArchiveEntry(
            title: title ?? "",
            content: content,
            pinned: pinned
        )
        return entry.asRecord()
    }

    func update(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord {
        let entries = try await synced.listArchiveEntries(query: nil)
        if let existing = entries.first(where: { $0.id == id }) {
            let entry = try await synced.updateArchiveEntry(
                id: id,
                title: title ?? existing.title,
                content: content,
                pinned: pinned ?? existing.isPinned
            )
            return entry.asRecord()
        }
        return try await local.update(id: id, title: title, content: content, pinned: pinned)
    }

    func updateMatching(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord? {
        let original = originalContentOrTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = try await mergedRecords(query: nil)
        guard let match = records.first(where: { $0.content == original || $0.title == original }) else {
            return nil
        }
        return try await update(id: match.id, title: match.title, content: updatedContent, pinned: match.pinned)
    }

    func delete(id: UUID) async throws {
        try await synced.deleteArchiveEntry(id: id)
        try await local.delete(id: id)
    }

    func deleteAll() async throws {
        try await synced.deleteAllArchiveEntries()
        try await local.deleteAll()
    }

    func retrieve(keyword: String, limit: Int) async throws -> [MemorySearchResult] {
        let records = try await mergedRecords(query: nil)
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return records
                .prefix(max(1, limit))
                .map { MemorySearchResult(record: $0, score: $0.pinned ? 2 : 1) }
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: limit)
    }

    private func mergedRecords(query: String?) async throws -> [MemoryRecord] {
        async let localRecords = local.list(query: query)
        async let syncedEntries = synced.listArchiveEntries(query: query)
        let locals = try await localRecords
        let entries = try await syncedEntries
        let syncedRecords = entries.map { $0.asRecord() }
        var seenContent = Set(syncedRecords.map(\.content))
        var merged = syncedRecords
        for record in locals where seenContent.contains(record.content) == false {
            seenContent.insert(record.content)
            merged.append(record)
        }
        return merged.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
