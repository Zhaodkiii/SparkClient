import Foundation

protocol DeepTutorMemoryStore: Sendable {
    func readAll() async throws -> [MemoryRecord]
    func savePreference(_ text: String) async throws -> MemoryRecord
    func updatePreference(id: UUID, text: String) async throws -> MemoryRecord
}

