import Foundation

final class AIConfigCenter {
    private let repository: any AISettingsRepository
    private let remoteProvider: (any AIRemoteConfigProvider)?
    private let runtimeStore: AIRuntimeStore
    private let runtimeConfigStore: AIRuntimeConfigStore
    private let sessionSnapshotStore: SessionSnapshotStore
    private let resolver: ScenarioPolicyResolver
    private let logger: Logger

    init(
        repository: any AISettingsRepository,
        remoteProvider: (any AIRemoteConfigProvider)? = nil,
        runtimeStore: AIRuntimeStore,
        runtimeConfigStore: AIRuntimeConfigStore,
        sessionSnapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        resolver: ScenarioPolicyResolver = ScenarioPolicyResolver(),
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.remoteProvider = remoteProvider
        self.runtimeStore = runtimeStore
        self.runtimeConfigStore = runtimeConfigStore
        self.sessionSnapshotStore = sessionSnapshotStore
        self.resolver = resolver
        self.logger = logger
    }

    private func resolvedOwnerAccountID(explicit explicitID: Int64?) async -> Int64? {
        if let explicitID {
            return explicitID
        }
        return await sessionSnapshotStore.load()?.accountID
    }

    func resolve(for scenario: AIScenario, preferredModelName: String? = nil) async throws -> AIResolvedConfig {
        let bundles = try await runtimeConfigStore.effectiveBundles()
        let resolved = try await resolver.resolve(
            scenario: scenario,
            bundles: bundles,
            runtimeStore: runtimeStore,
            preferredModelName: preferredModelName
        )
        logger.debug(
            "已解析场景=\(scenario.rawValue)，来源=\(resolved.source.rawValue)，模型=\(resolved.model)",
            module: .aiConfig
        )
        return resolved
    }

    /// 将快照写入 `AIRuntimeConfigStore`（含 `AISettingsSnapshot` 缓存与本地 bundle）。不绑定账号时沿用已缓存的 `ownerAccountID`。
    func rebuildRuntimeCache(from snapshot: AISettingsSnapshot) async {
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: nil)
        logger.debug("AI 运行时快照与场景 bundle 已更新", module: .aiConfig)
    }

    /// 设置页草稿：更新运行时内快照与 bundle，不覆盖已绑定的账号键。
    func applyDraftSnapshot(_ snapshot: AISettingsSnapshot) async {
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: nil)
        logger.debug("AI 运行时草稿快照已应用", module: .aiConfig)
    }

    /// 登录引导：按账号从仓储加载目录（bundle 种子仅在该账号首次初始化时入库），再写入 `AIRuntimeConfigStore`。
    /// - Parameter ownerAccountID: 与 `UserSession.accountID` 一致，避免仅依赖会话快照解析顺序。
    func prewarm(ownerAccountID: Int64? = nil) async {
        let source = ownerAccountID.map { "ownerAccountID=\($0)" } ?? "ownerAccountID=nil（由仓储解析会话）"
        logger.info("AIConfigCenter.prewarm 开始 \(source)", module: .aiConfig)
        let snapshot = await repository.loadSnapshot(ownerAccountID: ownerAccountID)
        let resolvedOwner = await resolvedOwnerAccountID(explicit: ownerAccountID)
        logger.info(
            "AIConfigCenter.prewarm 已从仓储拿到快照 厂商Key=\(snapshot.apiKeys.count) 模型=\(snapshot.allModels.count)，即将写入运行时缓存",
            module: .aiConfig
        )
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: resolvedOwner)
        logger.info("AIConfigCenter.prewarm 结束，运行时本地 bundle 已更新", module: .aiConfig)
    }

    func currentSnapshot(ownerAccountID: Int64? = nil) async -> AISettingsSnapshot {
        let resolved = await resolvedOwnerAccountID(explicit: ownerAccountID)
        let source = ownerAccountID.map { "显式 ownerAccountID=\($0)" } ?? "仓储解析会话"
        logger.debug("AIConfigCenter.currentSnapshot 读链路开始（\(source)，resolved=\(String(describing: resolved))）", module: .aiConfig)

        if let hit = await runtimeConfigStore.cachedSnapshotIfMatches(ownerAccountID: resolved) {
            logger.debug(
                "AIConfigCenter.currentSnapshot 命中内存缓存 厂商Key=\(hit.apiKeys.count) 模型=\(hit.allModels.count)",
                module: .aiConfig
            )
            return hit
        }

        let snapshot = await repository.loadSnapshot(ownerAccountID: ownerAccountID)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: resolved)
        logger.debug(
            "AIConfigCenter.currentSnapshot 已从仓储回填缓存 厂商Key=\(snapshot.apiKeys.count) 模型=\(snapshot.allModels.count)",
            module: .aiConfig
        )
        return snapshot
    }


    func effectiveScenarioBundles() async throws -> AIScenarioRemoteBundlesCollection {
        try await runtimeConfigStore.effectiveBundles()
    }

    func localScenarioBundles() async -> AIScenarioRemoteBundlesCollection? {
        await runtimeConfigStore.localScenarioBundles()
    }

    func proScenarioBundles() async -> AIScenarioRemoteBundlesCollection? {
        await runtimeConfigStore.proScenarioBundles()
    }

    func updateScenarioDefaultModel(_ modelName: String, for scenario: AIScenario) async {
        await runtimeConfigStore.updateScenarioDefaultModel(modelName, for: scenario)
        await persistScenarioPreferenceMutation { snapshot in
            snapshot.setScenarioDefaultModelName(modelName, for: scenario)
        }
    }

    func updateScenarioModelSource(_ source: AIModelSelectionSource, for scenario: AIScenario) async {
        await runtimeConfigStore.updateScenarioModelSource(source, for: scenario)
        await persistScenarioPreferenceMutation { snapshot in
            snapshot.setScenarioModelSource(source, for: scenario)
        }
    }

    func refreshRemoteConfig() async {
        guard let remoteProvider else { return }
        do {
            let patch = try await remoteProvider.fetchRemotePatch()
            await runtimeConfigStore.setProOverlay(patch.scenarioRemoteBundles, revision: patch.revision)
            logger.info(
                "远程 AI 场景模型已载入内存，revision=\(patch.revision ?? "unknown")",
                module: .aiConfig
            )
        } catch {
            logger.error("\(error)")
            logger.error("远程 AI 配置刷新失败：\(error.localizedDescription)", module: .aiConfig)
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

    func resetRuntimeCaches() async {
        await runtimeConfigStore.reset()
        await runtimeStore.clearAll()
    }

    private func persistScenarioPreferenceMutation(
        _ mutate: @Sendable (inout AISettingsSnapshot) -> Void
    ) async {
        let ownerAccountID = await resolvedOwnerAccountID(explicit: nil)
        var snapshot = await currentSnapshot(ownerAccountID: ownerAccountID)
        mutate(&snapshot)
        await runtimeConfigStore.applySnapshot(snapshot, ownerAccountID: ownerAccountID)
        do {
            try await repository.save(snapshot: snapshot, ownerAccountID: ownerAccountID)
        } catch {
            logger.error("AI 场景偏好持久化失败：\(error.localizedDescription)", module: .aiConfig)
        }
    }
}
