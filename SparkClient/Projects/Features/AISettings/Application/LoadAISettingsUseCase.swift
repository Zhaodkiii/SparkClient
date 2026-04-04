import Foundation

struct LoadAISettingsUseCase: Sendable {
    let repository: any AISettingsRepository

    func execute() async -> AISettingsSnapshot {
        await repository.loadSnapshot()
    }
}
