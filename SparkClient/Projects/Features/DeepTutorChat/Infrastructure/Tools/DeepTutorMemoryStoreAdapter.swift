import Foundation

struct DeepTutorMemoryStoreAdapter: DeepTutorMemoryStore {
    let loadUseCase: LoadMemoryArchiveUseCase
    let saveUseCase: SaveMemoryUseCase
    let updateUseCase: UpdateMemoryUseCase

    func readAll() async throws -> [MemoryRecord] {
        try await loadUseCase.execute(query: nil)
    }

    func savePreference(_ text: String) async throws -> MemoryRecord {
        try await saveUseCase.execute(title: "Preference", content: text, pinned: false)
    }

    func updatePreference(id: UUID, text: String) async throws -> MemoryRecord {
        try await updateUseCase.execute(id: id, title: "Preference", content: text, pinned: nil)
    }
}

