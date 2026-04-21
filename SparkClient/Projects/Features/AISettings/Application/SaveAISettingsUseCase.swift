import Foundation

struct SaveAISettingsUseCase: Sendable {
    let repository: any AISettingsRepository

    func execute(snapshot: AISettingsSnapshot, ownerAccountID: Int64? = nil) async throws {
        try await repository.save(snapshot: snapshot, ownerAccountID: ownerAccountID)
    }

    func execute(model: AllModels) async throws {
        try await repository.saveModel(model)
    }

    func execute(provider: APIKeys) async throws {
        try await repository.saveProvider(provider)
    }
}
