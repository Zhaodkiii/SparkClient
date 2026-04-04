import Foundation

struct AISettingsSnapshot: Codable, Equatable, Sendable {
    var chat: AIScenarioConfig
    var optimizationText: AIScenarioConfig
    var optimizationVisual: AIScenarioConfig
    var contextFolding: AIScenarioConfig
    var router: AIScenarioConfig
    var modelConfig: AIScenarioConfig
    var reportInterpretation: AIScenarioConfig
    var apiKeys: [APIKeys]
    var searchKeys: [SearchKeys]
    var toolKeys: [ToolKeys]
    var allModels: [AllModels]
    var userInfo: UserInfo
    var trial: AITrialState
    var trialModelPolicy: [AITrialModelPolicyItem]
    var promptRepo: [PromptRepo]
    var memoryArchive: [MemoryArchive]
    var translationDic: [TranslationDic]

    private static let defaultChatEndpoint = "https://api.sparkclient.local/v1/chat/completions"
    private static let defaultEmbedEndpoint = "https://api.sparkclient.local/v1/embeddings"

    static let `default` = AISettingsSnapshot(
        chat: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.2,
            maxTokens: 4096
        ),
        optimizationText: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.0,
            maxTokens: 4096
        ),
        optimizationVisual: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.2,
            maxTokens: 4096
        ),
        contextFolding: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.2,
            maxTokens: 4096
        ),
        router: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.2,
            maxTokens: 4096
        ),
        modelConfig: AIScenarioConfig(
            endpoint: defaultEmbedEndpoint,
            model: "spark-embedding-default",
            apiKey: nil,
            temperature: 0.0,
            maxTokens: 2048
        ),
        reportInterpretation: AIScenarioConfig(
            endpoint: defaultChatEndpoint,
            model: "spark-chat-default",
            apiKey: nil,
            temperature: 0.2,
            maxTokens: 4096
        ),
        apiKeys: AISettingsDefaults.apiKeys,
        searchKeys: AISettingsDefaults.searchKeys,
        toolKeys: AISettingsDefaults.toolKeys,
        allModels: AISettingsDefaults.allModels,
        userInfo: AISettingsDefaults.userInfo,
        trial: .inactive,
        trialModelPolicy: [],
        promptRepo: AISettingsDefaults.promptRepo,
        memoryArchive: AISettingsDefaults.memoryArchive,
        translationDic: AISettingsDefaults.translationDic
    )

    func config(for scenario: AIScenario) -> AIScenarioConfig {
        switch scenario {
        case .chat:
            return chat
        case .optimizationText:
            return optimizationText
        case .optimizationVisual:
            return optimizationVisual
        case .contextFolding:
            return contextFolding
        case .router:
            return router
        case .modelConfig:
            return modelConfig
        case .reportInterpretation:
            return reportInterpretation
        }
    }

    func trialPolicyConfig(for scenario: AIScenario) -> AIScenarioConfig? {
        guard trial.isActive else { return nil }
        return trialModelPolicy.first(where: { $0.scenario == scenario })?.config
    }
}

protocol AISettingsRepository: Sendable {
    func loadSnapshot() async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
}
