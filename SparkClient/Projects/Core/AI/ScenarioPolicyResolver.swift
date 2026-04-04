import Foundation

struct ScenarioPolicyResolver {
    func resolve(
        scenario: AIScenario,
        snapshot: AISettingsSnapshot,
        runtimeStore: AIRuntimeStore
    ) async throws -> AIResolvedConfig {
        if let runtimeConfig = await runtimeStore.runtimeOverride(for: scenario) {
            return try runtimeConfig.toResolvedConfig(source: .runtimeOverride)
        }

        if let trialConfig = snapshot.trialPolicyConfig(for: scenario) {
            return try trialConfig.toResolvedConfig(source: .trialPolicy)
        }

        let defaultConfig = snapshot.config(for: scenario)
        return try defaultConfig.toResolvedConfig(source: .localDefault)
    }
}
