import CoreData
import Foundation

final class CoreDataMemoryRepository: MemoryRepository, @unchecked Sendable {
    private enum EntityName {
        static let memory = "MemoryRecordEntity"
    }

    private enum Field {
        static let id = "id"
        static let ownerAccountID = "ownerAccountID"
        static let title = "title"
        static let content = "content"
        static let pinned = "pinned"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private enum UserDefaultsKey {
        static func preferences(_ accountID: Int64) -> String {
            "spark.memory.preferences.\(accountID)"
        }
    }

    private let coreDataStack: CoreDataStack
    private let sessionSnapshotStore: SessionSnapshotStore
    private let searchEngine: MemorySearchEngine
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        coreDataStack: CoreDataStack,
        sessionSnapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        searchEngine: MemorySearchEngine = MemorySearchEngine(),
        defaults: UserDefaults = .standard
    ) {
        self.coreDataStack = coreDataStack
        self.sessionSnapshotStore = sessionSnapshotStore
        self.searchEngine = searchEngine
        self.defaults = defaults
    }

    func loadPreferences() async -> MemoryPreferences {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            return .default
        }
        guard let data = defaults.data(forKey: UserDefaultsKey.preferences(ownerAccountID)),
              let preferences = try? decoder.decode(MemoryPreferences.self, from: data)
        else {
            return .default
        }
        return preferences
    }

    func savePreferences(_ preferences: MemoryPreferences) async throws {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        let data = try encoder.encode(preferences)
        defaults.set(data, forKey: UserDefaultsKey.preferences(ownerAccountID))
    }

    func list(query: String?) async throws -> [MemoryRecord] {
        guard let ownerAccountID = await currentOwnerAccountID() else { return [] }
        let records = try await fetchAll(ownerAccountID: ownerAccountID)
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else {
            return sortForArchive(records)
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: records.count).map(\.record)
    }

    func save(title: String?, content: String, pinned: Bool) async throws -> MemoryRecord {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else {
            throw MemoryRepositoryError.emptyContent
        }
        let trimmedTitle = normalizedTitle(title, content: trimmedContent)
        let now = Date()
        let record = MemoryRecord(
            title: trimmedTitle,
            content: trimmedContent,
            pinned: pinned,
            createdAt: now,
            updatedAt: now
        )

        try await coreDataStack.performBackgroundTask { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.memory, into: context)
            self.apply(record: record, ownerAccountID: ownerAccountID, to: object, preserveCreatedAt: false)
        }
        return record
    }

    func update(id: UUID, title: String?, content: String, pinned: Bool?) async throws -> MemoryRecord {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else {
            throw MemoryRepositoryError.emptyContent
        }

        return try await coreDataStack.performBackgroundTask { context in
            guard let object = try self.fetchObject(id: id, ownerAccountID: ownerAccountID, context: context) else {
                throw CocoaError(.managedObjectValidation)
            }
            var record = self.makeRecord(from: object)
            record.title = self.normalizedTitle(title, content: trimmedContent)
            record.content = trimmedContent
            if let pinned {
                record.pinned = pinned
            }
            record.updatedAt = Date()
            self.apply(record: record, ownerAccountID: ownerAccountID, to: object, preserveCreatedAt: true)
            return record
        }
    }

    func updateMatching(originalContentOrTitle: String, updatedContent: String) async throws -> MemoryRecord? {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        let original = originalContentOrTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = updatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard original.isEmpty == false, updated.isEmpty == false else {
            throw MemoryRepositoryError.emptyContent
        }

        return try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.memory)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(ownerAccountID),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "\(Field.content) == %@", original),
                    NSPredicate(format: "\(Field.title) == %@", original)
                ])
            ])
            guard let object = try context.fetch(request).first else {
                return nil
            }
            var record = self.makeRecord(from: object)
            record.content = updated
            record.title = self.normalizedTitle(record.title, content: updated)
            record.updatedAt = Date()
            self.apply(record: record, ownerAccountID: ownerAccountID, to: object, preserveCreatedAt: true)
            return record
        }
    }

    func delete(id: UUID) async throws {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        try await coreDataStack.performBackgroundTask { context in
            if let object = try self.fetchObject(id: id, ownerAccountID: ownerAccountID, context: context) {
                context.delete(object)
            }
        }
    }

    func deleteAll() async throws {
        guard let ownerAccountID = await currentOwnerAccountID() else {
            throw MemoryRepositoryError.notSignedIn
        }
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.memory)
            request.predicate = self.ownerPredicate(ownerAccountID)
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
    }

    func retrieve(keyword: String, limit: Int) async throws -> [MemorySearchResult] {
        guard let ownerAccountID = await currentOwnerAccountID() else { return [] }
        let records = try await fetchAll(ownerAccountID: ownerAccountID)
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return sortForArchive(records)
                .prefix(max(1, limit))
                .map { MemorySearchResult(record: $0, score: $0.pinned ? 2 : 1) }
        }
        return searchEngine.search(records: records, keyword: trimmed, limit: limit)
    }

    private func currentOwnerAccountID() async -> Int64? {
        await sessionSnapshotStore.load()?.accountID
    }

    private func fetchAll(ownerAccountID: Int64) async throws -> [MemoryRecord] {
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.memory)
            request.predicate = self.ownerPredicate(ownerAccountID)
            request.sortDescriptors = [
                NSSortDescriptor(key: Field.pinned, ascending: false),
                NSSortDescriptor(key: Field.updatedAt, ascending: false)
            ]
            return try context.fetch(request).map(self.makeRecord)
        }
    }

    private func fetchObject(
        id: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.memory)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "\(Field.id) == %@", id as CVarArg)
        ])
        return try context.fetch(request).first
    }

    private func ownerPredicate(_ ownerAccountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", ownerAccountID)
    }

    private func sortForArchive(_ records: [MemoryRecord]) -> [MemoryRecord] {
        records.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func normalizedTitle(_ title: String?, content: String) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedTitle.isEmpty == false {
            return String(trimmedTitle.prefix(40))
        }
        return String(content.prefix(20))
    }

    private func makeRecord(from object: NSManagedObject) -> MemoryRecord {
        MemoryRecord(
            id: object.value(forKey: Field.id) as? UUID ?? UUID(),
            title: object.value(forKey: Field.title) as? String ?? "",
            content: object.value(forKey: Field.content) as? String ?? "",
            pinned: object.value(forKey: Field.pinned) as? Bool ?? false,
            createdAt: object.value(forKey: Field.createdAt) as? Date ?? Date(),
            updatedAt: object.value(forKey: Field.updatedAt) as? Date ?? Date()
        )
    }

    private func apply(
        record: MemoryRecord,
        ownerAccountID: Int64,
        to object: NSManagedObject,
        preserveCreatedAt: Bool
    ) {
        object.setValue(record.id, forKey: Field.id)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(record.title, forKey: Field.title)
        object.setValue(record.content, forKey: Field.content)
        object.setValue(record.pinned, forKey: Field.pinned)
        if preserveCreatedAt == false {
            object.setValue(record.createdAt, forKey: Field.createdAt)
        }
        object.setValue(record.updatedAt, forKey: Field.updatedAt)
    }
}
