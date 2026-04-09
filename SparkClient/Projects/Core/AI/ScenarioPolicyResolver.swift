import Foundation

/// 场景策略解析器
/// 负责按优先级解析当前场景最终生效的 AI 配置
/// 优先级：运行时覆盖 > 试用策略（默认模型）> 本地默认配置
struct ScenarioPolicyResolver {

    /// 解析指定场景的最终生效 AI 配置
    /// - Parameters:
    ///   - scenario: 业务场景
    ///   - snapshot: AI 设置快照
    ///   - runtimeStore: 运行时状态存储（用于读取临时覆盖配置）
    /// - Returns: 最终解析完成的 AI 配置
    func resolve(
        scenario: AIScenario,
        snapshot: AISettingsSnapshot,
        runtimeStore: AIRuntimeStore
    ) async throws -> AIResolvedConfig {
        // 1. 优先使用运行时覆盖配置（最高优先级）
        if let runtimeConfig = await runtimeStore.runtimeOverride(for: scenario) {
            return try runtimeConfig.toResolvedConfig(source: .runtimeOverride)
        }

        // 2. 其次使用试用/活动策略配置（后台下发的默认模型）
        if let trialConfig = snapshot.trialPolicyConfig(for: scenario) {
            return try trialConfig.toResolvedConfig(source: .trialPolicy)
        }

        // 3. 最后使用本地默认配置（最低优先级）
        let defaultConfig = snapshot.config(for: scenario)
        return try defaultConfig.toResolvedConfig(source: .localDefault)
    }
}
