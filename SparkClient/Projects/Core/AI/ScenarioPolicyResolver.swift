import Foundation

/// 场景策略解析器：按优先级解析当前场景最终生效的 AI 配置。
/// 优先级：显式首选模型 > 运行时覆盖 > bundle 默认解析链。
struct ScenarioPolicyResolver {

    func resolve(
        scenario: AIScenario,
        bundles: AIScenarioRemoteBundlesCollection,
        runtimeStore: AIRuntimeStore,
        preferredModelName: String? = nil
    ) async throws -> AIResolvedConfig {
        let trimmedPreferred = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPreferred, trimmedPreferred.isEmpty == false {
            if let row = bundles.resolveRow(for: scenario, preferredModelName: trimmedPreferred) {
                return try row.asScenarioConfig().toResolvedConfig(source: row.configSource)
            }
            throw AIConfigError.missingModelForScenario(scenario)
        }

        if let runtimeConfig = await runtimeStore.runtimeOverride(for: scenario) {
            return try runtimeConfig.toResolvedConfig(source: .runtimeOverride)
        }

        guard let defaultRow = bundles.resolveRow(for: scenario, preferredModelName: nil) else {
            throw AIConfigError.missingModelForScenario(scenario)
        }
        return try defaultRow.asScenarioConfig().toResolvedConfig(source: defaultRow.configSource)
    }
}
