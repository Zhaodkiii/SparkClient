import Foundation

final class AIConfigCenter {
    private let repository: any AISettingsRepository
    private let remoteProvider: (any AIRemoteConfigProvider)?
    private let runtimeStore: AIRuntimeStore
    private let resolver: ScenarioPolicyResolver
    private let logger: Logger

    init(
        repository: any AISettingsRepository,
        remoteProvider: (any AIRemoteConfigProvider)? = nil,
        runtimeStore: AIRuntimeStore,
        resolver: ScenarioPolicyResolver = ScenarioPolicyResolver(),
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.remoteProvider = remoteProvider
        self.runtimeStore = runtimeStore
        self.resolver = resolver
        self.logger = logger
    }

    func resolve(for scenario: AIScenario) async throws -> AIResolvedConfig {
        let snapshot = await repository.loadSnapshot()
        let resolved = try await resolver.resolve(
            scenario: scenario,
            snapshot: snapshot,
            runtimeStore: runtimeStore
        )
        logger.debug(
            "已解析场景=\(scenario.rawValue)，来源=\(resolved.source.rawValue)，模型=\(resolved.model)",
            module: .aiConfig
        )
        return resolved
    }

    func prewarm() async {
        _ = await repository.loadSnapshot()
        logger.debug("AI 配置已预热", module: .aiConfig)
    }

    func currentSnapshot() async -> AISettingsSnapshot {
        await repository.loadSnapshot()
    }

    func refreshRemoteConfig() async {
        guard let remoteProvider else { return }

        let localSnapshot = await repository.loadSnapshot()
        do {
            let patch = try await remoteProvider.fetchRemotePatch()
            let merged = localSnapshot.merging(remotePatch: patch)
            guard merged != localSnapshot else {
                logger.debug("远程 AI 配置已拉取，与本地无差异", module: .aiConfig)
                return
            }

            try await repository.save(snapshot: merged)
            logger.info(
                "远程 AI 配置已合并，revision=\(patch.revision ?? "unknown")",
                module: .aiConfig
            )
        } catch {
            logger.warning("远程 AI 配置刷新失败：\(error.localizedDescription)", module: .aiConfig)
        }
    }

    func setRuntimeOverride(_ config: AIScenarioConfig, for scenario: AIScenario) async {
        await runtimeStore.setOverride(config, for: scenario)
    }

    func clearRuntimeOverride(for scenario: AIScenario) async {
        await runtimeStore.clearOverride(for: scenario)
    }

    func clearRuntimeOverrides() async {
        await runtimeStore.clearAll()
    }
}
