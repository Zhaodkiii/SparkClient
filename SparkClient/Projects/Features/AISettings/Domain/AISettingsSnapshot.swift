import Foundation

struct AISettingsSnapshot: Codable, Equatable, Sendable {
    var chat: AIScenarioConfig
    var medicalExtraction: AIScenarioConfig
    var embedding: AIScenarioConfig
    var apiKeys: [APIKeys]
    var searchKeys: [SearchKeys]
    var toolKeys: [ToolKeys]
    var allModels: [AllModels]
    var userInfo: UserInfo
    var promptRepo: [PromptRepo]
    var memoryArchive: [MemoryArchive]
    var translationDic: [TranslationDic]

    static let `default` = AISettingsSnapshot(
        chat: AIScenarioConfig(
            endpoint: "https://api.deepseek.com/v1/chat/completions",
            model: "deepseek-chat",
            apiKey: "sk-5ee7fe714ff54ad98d7658eb819ef982",
            temperature: 0.2,
            maxTokens: 4096
        ),
        medicalExtraction: AIScenarioConfig(
            endpoint: "https://api.sparkclient.local/v1/chat/completions",
            model: "spark-medical-extraction",
            apiKey: nil,
            temperature: 0.0,
            maxTokens: 4096
        ),
        embedding: AIScenarioConfig(
            endpoint: "https://api.sparkclient.local/v1/embeddings",
            model: "spark-embedding-default",
            apiKey: nil,
            temperature: 0.0,
            maxTokens: 2048
        ),
        apiKeys: AISettingsDefaults.apiKeys,
        searchKeys: AISettingsDefaults.searchKeys,
        toolKeys: AISettingsDefaults.toolKeys,
        allModels: AISettingsDefaults.allModels,
        userInfo: AISettingsDefaults.userInfo,
        promptRepo: AISettingsDefaults.promptRepo,
        memoryArchive: AISettingsDefaults.memoryArchive,
        translationDic: AISettingsDefaults.translationDic
    )

    func config(for scenario: AIScenario) -> AIScenarioConfig {
        switch scenario {
        case .chat:
            return chat
        case .medicalExtraction:
            return medicalExtraction
        case .embedding:
            return embedding
        }
    }
}

protocol AISettingsRepository: Sendable {
    func loadSnapshot() async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
}
