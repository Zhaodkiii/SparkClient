import Foundation

/// 当前登录账号的 AI 运行时缓存：本地场景 bundle + Pro 内存 overlay + 与 bundle 同源的 `AISettingsSnapshot`。
actor AIRuntimeConfigStore {
    private var localBundles: AIScenarioRemoteBundlesCollection?
    private var proBundles: AIScenarioRemoteBundlesCollection?
    private(set) var proRevision: String?

    /// 与 `localBundles` 同源的上次快照；供设置页与推理侧避免重复读库。
    private var cachedSnapshot: AISettingsSnapshot?
    /// 与 `cachedSnapshot` 绑定的账号；`nil` 表示尚未与具体账号绑定（仅草稿更新时可能保持 `nil`）。
    private var cachedOwnerAccountID: Int64?

    /// 写入快照并重建各场景本地 bundle。
    /// - Parameter ownerAccountID: 非 `nil` 时绑定缓存键；为 `nil` 时仅更新快照内容（设置页草稿），不覆盖已绑定账号。
    func applySnapshot(_ snapshot: AISettingsSnapshot, ownerAccountID: Int64?) {
        if let ownerAccountID {
            cachedOwnerAccountID = ownerAccountID
        }
        cachedSnapshot = snapshot
        localBundles = AILocalScenarioBundleBuilder.buildCollection(
            allModels: snapshot.allModels,
            apiKeys: snapshot.apiKeys,
            scenarioDefaults: AIScenarioDefaultModelStore.allScenarioDefaults(fallback: snapshot.scenarioDefaultModels)
        )
    }

    /// 仅当缓存存在且账号与当前解析一致时返回，避免跨账号误用。
    func cachedSnapshotIfMatches(ownerAccountID: Int64?) -> AISettingsSnapshot? {
        guard let cached = cachedSnapshot else { return nil }
        guard cachedOwnerAccountID == ownerAccountID else { return nil }
        return cached
    }

    func setProOverlay(_ bundles: AIScenarioRemoteBundlesCollection?, revision: String?) {
        proBundles = bundles
        proRevision = revision
    }

    func clearProOverlay() {
        proBundles = nil
        proRevision = nil
    }

    func reset() {
        localBundles = nil
        proBundles = nil
        proRevision = nil
        cachedSnapshot = nil
        cachedOwnerAccountID = nil
    }

    func localScenarioBundles() -> AIScenarioRemoteBundlesCollection? {
        localBundles
    }

    func proScenarioBundles() -> AIScenarioRemoteBundlesCollection? {
        proBundles
    }

    /// 场景默认模型变更后，同步更新运行时缓存快照与已缓存 bundle。
    func updateScenarioDefaultModel(_ modelName: String, for scenario: AIScenario) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        if cachedSnapshot != nil {
            cachedSnapshot?.scenarioDefaultModels[scenario.rawValue] = trimmed
        }

        if localBundles != nil {
            localBundles = applyingDefaultModel(trimmed, to: localBundles, for: scenario)
        }
        if proBundles != nil {
            proBundles = applyingDefaultModel(trimmed, to: proBundles, for: scenario)
        }
    }

    /// 合并后的最终场景集合。
    func effectiveBundles() throws -> AIScenarioRemoteBundlesCollection {
        guard let local = localBundles else {
            throw AIConfigError.runtimeNotBootstrapped
        }
        var merged = AIRuntimeConfigAssembler.merge(local: local, pro: proBundles)
        let fallbackDefaults = cachedSnapshot?.scenarioDefaultModels ?? [:]
        for scenario in AIScenario.allCases {
            let preferredModelName = AIScenarioDefaultModelStore.read(for: scenario)
                ?? fallbackDefaults[scenario.rawValue]
            guard let preferredModelName,
                  preferredModelName.isEmpty == false
            else { continue }
            var bundle = merged.bundle(for: scenario)
            guard bundle.models.contains(where: { $0.name == preferredModelName }) else { continue }
            bundle.defaultModelName = preferredModelName
            bundle.models = bundle.models.map { row in
                var normalized = row
                normalized.isDefault = (row.name == preferredModelName)
                return normalized
            }
            merged.setBundle(bundle, for: scenario)
        }
        return merged
    }

    private func applyingDefaultModel(
        _ modelName: String,
        to bundles: AIScenarioRemoteBundlesCollection?,
        for scenario: AIScenario
    ) -> AIScenarioRemoteBundlesCollection? {
        guard var bundles else { return nil }
        var bundle = bundles.bundle(for: scenario)
        guard bundle.models.contains(where: { $0.name == modelName }) else { return bundles }
        bundle.defaultModelName = modelName
        bundle.models = bundle.models.map { row in
            var copy = row
            copy.isDefault = (row.name == modelName)
            return copy
        }
        bundles.setBundle(bundle, for: scenario)
        return bundles
    }
}
