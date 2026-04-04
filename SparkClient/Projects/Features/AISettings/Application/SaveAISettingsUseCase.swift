import Foundation

struct SaveAISettingsUseCase: Sendable {
    let repository: any AISettingsRepository

    func execute(snapshot: AISettingsSnapshot) async throws {
        try await repository.save(snapshot: snapshot)
    }
}
