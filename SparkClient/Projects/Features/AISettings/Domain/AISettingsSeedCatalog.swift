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
