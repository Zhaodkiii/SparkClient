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
    /// Server `scenarios` multi-model catalog; `nil` for legacy persisted snapshots until the next remote merge.
    var scenarioRemoteBundles: AIScenarioRemoteBundlesCollection?
    /// Per-scenario chosen model name (`AIScenario.rawValue` → model id); empty uses bundle default.
    var scenarioSelectedModel: [String: String]
    /// 试用期内，在「对话」模型选择器中**隐藏**的试用模型 id（`trialModelPolicy` 中 `chat` 场景）；空表示未手动排除任何试用模型。
    var trialChatPickerDisabledModelNames: [String]

    private static let defaultChatEndpoint = "https://api.sparkclient.local/v1/chat/completions"
    private static let defaultEmbedEndpoint = "https://api.sparkclient.local/v1/embeddings"

    init(
        chat: AIScenarioConfig,
        optimizationText: AIScenarioConfig,
        optimizationVisual: AIScenarioConfig,
        contextFolding: AIScenarioConfig,
        router: AIScenarioConfig,
        modelConfig: AIScenarioConfig,
        reportInterpretation: AIScenarioConfig,
        apiKeys: [APIKeys],
        searchKeys: [SearchKeys],
        toolKeys: [ToolKeys],
        allModels: [AllModels],
        userInfo: UserInfo,
        trial: AITrialState,
        trialModelPolicy: [AITrialModelPolicyItem],
        promptRepo: [PromptRepo],
        memoryArchive: [MemoryArchive],
        translationDic: [TranslationDic],
        scenarioRemoteBundles: AIScenarioRemoteBundlesCollection?,
        scenarioSelectedModel: [String: String],
        trialChatPickerDisabledModelNames: [String] = []
    ) {
        self.chat = chat
        self.optimizationText = optimizationText
        self.optimizationVisual = optimizationVisual
        self.contextFolding = contextFolding
        self.router = router
        self.modelConfig = modelConfig
        self.reportInterpretation = reportInterpretation
        self.apiKeys = apiKeys
        self.searchKeys = searchKeys
        self.toolKeys = toolKeys
        self.allModels = allModels
        self.userInfo = userInfo
        self.trial = trial
        self.trialModelPolicy = trialModelPolicy
        self.promptRepo = promptRepo
        self.memoryArchive = memoryArchive
        self.translationDic = translationDic
        self.scenarioRemoteBundles = scenarioRemoteBundles
        self.scenarioSelectedModel = scenarioSelectedModel
        self.trialChatPickerDisabledModelNames = trialChatPickerDisabledModelNames
    }

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
        translationDic: AISettingsDefaults.translationDic,
        scenarioRemoteBundles: AIScenarioRemoteBundlesCollection.seededFromFlatSnapshots(
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
            )
        ),
        scenarioSelectedModel: [:],
        trialChatPickerDisabledModelNames: []
    )

    enum CodingKeys: String, CodingKey {
        case chat
        case optimizationText
        case optimizationVisual
        case contextFolding
        case router
        case modelConfig
        case reportInterpretation
        case apiKeys
        case searchKeys
        case toolKeys
        case allModels
        case userInfo
        case trial
        case trialModelPolicy
        case promptRepo
        case memoryArchive
        case translationDic
        case scenarioRemoteBundles
        case scenarioSelectedModel
        case trialChatPickerDisabledModelNames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chat = try c.decode(AIScenarioConfig.self, forKey: .chat)
        optimizationText = try c.decode(AIScenarioConfig.self, forKey: .optimizationText)
        optimizationVisual = try c.decode(AIScenarioConfig.self, forKey: .optimizationVisual)
        contextFolding = try c.decode(AIScenarioConfig.self, forKey: .contextFolding)
        router = try c.decode(AIScenarioConfig.self, forKey: .router)
        modelConfig = try c.decode(AIScenarioConfig.self, forKey: .modelConfig)
        reportInterpretation = try c.decode(AIScenarioConfig.self, forKey: .reportInterpretation)
        apiKeys = try c.decode([APIKeys].self, forKey: .apiKeys)
        searchKeys = try c.decode([SearchKeys].self, forKey: .searchKeys)
        toolKeys = try c.decode([ToolKeys].self, forKey: .toolKeys)
        allModels = try c.decode([AllModels].self, forKey: .allModels)
        userInfo = try c.decode(UserInfo.self, forKey: .userInfo)
        trial = try c.decode(AITrialState.self, forKey: .trial)
        trialModelPolicy = try c.decode([AITrialModelPolicyItem].self, forKey: .trialModelPolicy)
        promptRepo = try c.decode([PromptRepo].self, forKey: .promptRepo)
        memoryArchive = try c.decode([MemoryArchive].self, forKey: .memoryArchive)
        translationDic = try c.decode([TranslationDic].self, forKey: .translationDic)
        scenarioRemoteBundles = try c.decodeIfPresent(AIScenarioRemoteBundlesCollection.self, forKey: .scenarioRemoteBundles)
        scenarioSelectedModel = try c.decodeIfPresent([String: String].self, forKey: .scenarioSelectedModel) ?? [:]
        trialChatPickerDisabledModelNames = try c.decodeIfPresent([String].self, forKey: .trialChatPickerDisabledModelNames) ?? []
        if scenarioRemoteBundles == nil {
            scenarioRemoteBundles = AIScenarioRemoteBundlesCollection.seededFromFlatSnapshots(
                chat: chat,
                optimizationText: optimizationText,
                optimizationVisual: optimizationVisual,
                contextFolding: contextFolding,
                router: router,
                modelConfig: modelConfig,
                reportInterpretation: reportInterpretation
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chat, forKey: .chat)
        try c.encode(optimizationText, forKey: .optimizationText)
        try c.encode(optimizationVisual, forKey: .optimizationVisual)
        try c.encode(contextFolding, forKey: .contextFolding)
        try c.encode(router, forKey: .router)
        try c.encode(modelConfig, forKey: .modelConfig)
        try c.encode(reportInterpretation, forKey: .reportInterpretation)
        try c.encode(apiKeys, forKey: .apiKeys)
        try c.encode(searchKeys, forKey: .searchKeys)
        try c.encode(toolKeys, forKey: .toolKeys)
        try c.encode(allModels, forKey: .allModels)
        try c.encode(userInfo, forKey: .userInfo)
        try c.encode(trial, forKey: .trial)
        try c.encode(trialModelPolicy, forKey: .trialModelPolicy)
        try c.encode(promptRepo, forKey: .promptRepo)
        try c.encode(memoryArchive, forKey: .memoryArchive)
        try c.encode(translationDic, forKey: .translationDic)
        try c.encodeIfPresent(scenarioRemoteBundles, forKey: .scenarioRemoteBundles)
        try c.encode(scenarioSelectedModel, forKey: .scenarioSelectedModel)
        try c.encode(trialChatPickerDisabledModelNames, forKey: .trialChatPickerDisabledModelNames)
    }

    func config(for scenario: AIScenario) -> AIScenarioConfig {
        switch scenario {
        case .chat:
            return chat
        case .medicalStructuredExtraction:
            // 新增医疗结构化抽取场景：当前快照未单独持有字段，先复用文本抽取配置。
            return optimizationText
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

    /// Trial rows for this scenario; priority: `scenarioSelectedModel` match → `isDefault` → first.
    func trialPolicyConfig(for scenario: AIScenario) -> AIScenarioConfig? {
        guard trial.isActive else { return nil }
        let items = trialModelPolicy.filter { $0.scenario == scenario }
        guard items.isEmpty == false else { return nil }
        let sel = scenarioSelectedModel[scenario.rawValue]
        if let sel, let hit = items.first(where: { $0.config.model == sel }) {
            return hit.config
        }
        if let hit = items.first(where: { $0.isDefault }) {
            return hit.config
        }
        return items.first?.config
    }

    mutating func materializeAllScenariosFromBundles() {
        guard let bundles = scenarioRemoteBundles else { return }
        for scenario in AIScenario.allCases {
            let bundle = bundles.bundle(for: scenario)
            let preferred = scenarioSelectedModel[scenario.rawValue]
            guard let row = bundle.resolveRow(preferredModelName: preferred) else { continue }
            let config = row.asScenarioConfig()
            switch scenario {
            case .chat:
                chat = config
            case .medicalStructuredExtraction:
                // 新增场景兼容写回：先落到文本抽取配置，避免旧快照结构破坏兼容性。
                optimizationText = config
            case .optimizationText:
                optimizationText = config
            case .optimizationVisual:
                optimizationVisual = config
            case .contextFolding:
                contextFolding = config
            case .router:
                router = config
            case .modelConfig:
                modelConfig = config
            case .reportInterpretation:
                reportInterpretation = config
            }
        }
    }

    mutating func pruneInvalidScenarioSelections() {
        guard let bundles = scenarioRemoteBundles else { return }
        for scenario in AIScenario.allCases {
            guard let name = scenarioSelectedModel[scenario.rawValue] else { continue }
            let bundle = bundles.bundle(for: scenario)
            if bundle.models.contains(where: { $0.model == name }) == false {
                scenarioSelectedModel[scenario.rawValue] = nil
            }
        }
    }
}

protocol AISettingsRepository: Sendable {
    func loadSnapshot() async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
}
