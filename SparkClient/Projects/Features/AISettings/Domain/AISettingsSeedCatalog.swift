import Foundation

enum AISettingsSeedCatalog {
    static let version = 3

    static func getModelList() -> [AllModels] {
        AISettingsDefaults.allModels
    }

    static func getAPIKeyList() -> [APIKeys] {
        AISettingsDefaults.apiKeys
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

    static func getDefaultUserInfo() -> UserInfo {
        AISettingsDefaults.userInfo
    }
}

// MARK: - Compatibility with legacy preload naming

func getModelList() -> [AllModels] {
    AISettingsSeedCatalog.getModelList()
}

func getKeyList() -> [APIKeys] {
    AISettingsSeedCatalog.getAPIKeyList()
}

func getSearchKeyList() -> [SearchKeys] {
    AISettingsSeedCatalog.getSearchKeyList()
}

func getToolKeyList() -> [ToolKeys] {
    AISettingsSeedCatalog.getToolKeyList()
}
