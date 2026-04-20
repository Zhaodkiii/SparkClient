import Foundation

extension AISettingsSnapshot {
    var defaultThreadImageDeliveryModeRaw: String {
        ChatThreadImageDeliveryMode.directMultimodal.rawValue
    }

    /// 由本地目录构建的场景 bundle（不含 Pro 覆盖；用于设置页与即时展示）。
    func localScenarioBundles() -> AIScenarioRemoteBundlesCollection {
        AILocalScenarioBundleBuilder.buildCollection(
            allModels: allModels,
            apiKeys: apiKeys,
            scenarioDefaults: scenarioDefaultModels
        )
    }

    func resolveScenarioRow(
        for scenario: AIScenario,
        preferredModelName: String? = nil
    ) -> AIScenarioRemoteModelRow? {
        let bundles = localScenarioBundles()
        let trimmed = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = (trimmed?.isEmpty == false) ? trimmed : nil
        return bundles.resolveRow(for: scenario, preferredModelName: preferred)
    }

    func shouldOfferTrialModelInChatPicker(modelName: String) -> Bool {
        trialChatPickerDisabledModelNames.contains(modelName) == false
    }
}
