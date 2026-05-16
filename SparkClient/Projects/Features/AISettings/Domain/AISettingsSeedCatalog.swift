import Foundation

enum AISettingsSeedCatalog {
    static let version = 6

    static func getModelList() -> [AllModels] {
        AISettingsSeedLoader.loadAllModels() ?? []
    }

    static func getScenarioBindings() -> [AIScenarioModelBinding] {
        AISettingsSeedLoader.loadScenarioBindings() ?? []
    }

    static func getScenarioBindings(for models: [AllModels]) -> [AIScenarioModelBinding] {
        AISettingsSeedLoader.loadScenarioBindings(for: models) ?? []
    }

    static func getAPIKeyList() -> [APIKeys] {
        AISettingsSeedLoader.loadAPIKeys() ?? []
    }

    static func getSearchKeyList() -> [SearchKeys] {
        AISettingsDefaults.searchKeys
    }

    static func getToolKeyList() -> [ToolKeys] {
        AISettingsDefaults.toolKeys
    }

    static func getPromptList() -> [PromptRepo] {
        AISettingsDefaults.promptRepo
    }

    static func getDefaultSearchToolPreferences() -> AISearchToolPreferences {
        AISettingsDefaults.searchToolPreferences
    }
}
