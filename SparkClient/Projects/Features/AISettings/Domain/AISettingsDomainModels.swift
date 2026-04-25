import Foundation

enum AIRecordSource: String, Codable, CaseIterable, Sendable {
    case system
    case custom
    case pro
}

enum AIModelIdentity: String, Codable, CaseIterable, Sendable {
    case model
    case agent
}

enum AIModelSelectionSource: String, Codable, CaseIterable, Sendable {
    case localKey
    case trial
}

enum AIProviderIdentifier {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9_\\-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }
}

struct APIKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var providerID: String
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var help: String
    var from: String
    var privacyPolicyURL: String
    var isEnabled: Bool
    var source: AIRecordSource
    var privacyPolicyAccepted: Bool
    var privacyPolicyAcceptedAt: Date?
    var timestamp: Date

    var isHidden: Bool {
        get { !isEnabled }
        set { isEnabled = !newValue }
    }

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        help: String,
        from: String = AIRecordSource.system.rawValue,
        privacyPolicyURL: String = "",
        isEnabled: Bool = true,
        source: AIRecordSource,
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.help = help
        self.from = from
        self.privacyPolicyURL = privacyPolicyURL
        self.isEnabled = isEnabled
        self.source = source
        self.privacyPolicyAccepted = privacyPolicyAccepted
        self.privacyPolicyAcceptedAt = privacyPolicyAcceptedAt
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        isHidden: Bool,
        help: String,
        source: AIRecordSource,
        privacyPolicyURL: String = "",
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            providerID: providerID,
            name: name,
            company: company,
            key: key,
            requestURL: requestURL,
            help: help,
            from: source.rawValue,
            privacyPolicyURL: privacyPolicyURL,
            isEnabled: !isHidden,
            source: source,
            privacyPolicyAccepted: privacyPolicyAccepted,
            privacyPolicyAcceptedAt: privacyPolicyAcceptedAt,
            timestamp: timestamp
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case providerID
        case name
        case company
        case key
        case requestURL
        case help
        case from
        case privacyPolicyURL
        case isEnabled
        case source
        case privacyPolicyAccepted
        case privacyPolicyAcceptedAt
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        company = try container.decode(String.self, forKey: .company)
        providerID = AIProviderIdentifier.normalize(
            try container.decodeIfPresent(String.self, forKey: .providerID) ?? company
        )
        key = try container.decode(String.self, forKey: .key)
        requestURL = try container.decode(String.self, forKey: .requestURL)
        help = try container.decodeIfPresent(String.self, forKey: .help) ?? ""
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? AIRecordSource.system.rawValue
        privacyPolicyURL = try container.decodeIfPresent(String.self, forKey: .privacyPolicyURL) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .source) ?? AIRecordSource(rawValue: from.lowercased()) ?? .system
        privacyPolicyAccepted = try container.decodeIfPresent(Bool.self, forKey: .privacyPolicyAccepted) ?? false
        privacyPolicyAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .privacyPolicyAcceptedAt)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}

struct SearchKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var searchClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date
}

struct ToolKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var toolClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date
}

struct AllModels: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var displayName: String
    var identity: AIModelIdentity
    var position: Int
    var providerID: String
    var company: String
    var price: Int
    var isEnabled: Bool
    var supportsSearch: Bool
    var supportsTextGen: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportReasoningChange: Bool
    var supportsImageGen: Bool
    var supportsVoiceGen: Bool
    var supportsToolUse: Bool
    var systemProvision: String
    var icon: String
    var briefDescription: String
    var characterDesign: String
    var aiScenarios: [String]
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var baseModelName: String?
    var localFilename: String?
    var source: AIRecordSource
    var timestamp: Date

    var isHidden: Bool {
        get { !isEnabled }
        set { isEnabled = !newValue }
    }

    var priceTier: Int {
        get { price }
        set { price = newValue }
    }

    var supportsText: Bool {
        get { supportsTextGen }
        set { supportsTextGen = newValue }
    }

    var reasoningControllable: Bool {
        get { supportReasoningChange }
        set { supportReasoningChange = newValue }
    }

    var iconSymbol: String? {
        get { icon.isEmpty ? nil : icon }
        set { icon = newValue ?? "" }
    }

    var systemPrompt: String? {
        get { systemProvision.isEmpty ? nil : systemProvision }
        set { systemProvision = newValue ?? "" }
    }

    /// 场景选择：可为空，表示不限定场景。
    var selectedAIScenarios: Set<AIScenario> {
        get { Set(aiScenarios.compactMap(AIScenario.init(rawValue:))) }
        set { aiScenarios = newValue.map(\.rawValue).sorted() }
    }

    /// 工具选择：空数组视为“默认全选”，哨兵值视为“明确全不选”。
    var selectedToolNames: Set<String> {
        get {
            SparkToolName.selectedSet(fromStoredToolNames: aiToolScenarios)
        }
        set {
            aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: newValue)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        price: Int = 0,
        isEnabled: Bool = true,
        supportsSearch: Bool,
        supportsTextGen: Bool = true,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportReasoningChange: Bool = false,
        supportsImageGen: Bool,
        supportsVoiceGen: Bool,
        supportsToolUse: Bool,
        systemProvision: String = "",
        icon: String = "",
        briefDescription: String = "",
        characterDesign: String = "",
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        baseModelName: String? = nil,
        localFilename: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.position = position
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.company = company
        self.price = price
        self.isEnabled = isEnabled
        self.supportsSearch = supportsSearch
        self.supportsTextGen = supportsTextGen
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.supportsImageGen = supportsImageGen
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsToolUse = supportsToolUse
        self.systemProvision = systemProvision
        self.icon = icon
        self.briefDescription = briefDescription
        self.characterDesign = characterDesign
        self.aiScenarios = aiScenarios
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.baseModelName = baseModelName
        self.localFilename = localFilename
        self.source = source
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        isHidden: Bool,
        supportsSearch: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportsToolUse: Bool,
        supportsVoiceGen: Bool,
        supportsImageGen: Bool,
        iconSymbol: String? = nil,
        baseModelName: String? = nil,
        localFilename: String? = nil,
        systemPrompt: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date(),
        priceTier: Int = 0,
        supportsText: Bool = true,
        reasoningControllable: Bool = false,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = []
    ) {
        self.init(
            id: id,
            name: name,
            displayName: displayName,
            identity: identity,
            position: position,
            providerID: providerID,
            company: company,
            price: priceTier,
            isEnabled: !isHidden,
            supportsSearch: supportsSearch,
            supportsTextGen: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: reasoningControllable,
            supportsImageGen: supportsImageGen,
            supportsVoiceGen: supportsVoiceGen,
            supportsToolUse: supportsToolUse,
            systemProvision: systemPrompt ?? "",
            icon: iconSymbol ?? "",
            briefDescription: "",
            characterDesign: "",
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            baseModelName: baseModelName,
            localFilename: localFilename,
            source: source,
            timestamp: timestamp
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case identity
        case position
        case providerID
        case company
        case price
        case isEnabled
        case supportsSearch
        case supportsTextGen
        case supportsMultimodal
        case supportsReasoning
        case supportReasoningChange
        case supportsImageGen
        case supportsVoiceGen
        case supportsToolUse
        case systemProvision
        case icon
        case briefDescription
        case characterDesign
        case aiScenarios
        case aiToolScenarios
        case relatedTaskCodes
        case baseModelName
        case localFilename
        case source
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        identity = try container.decodeIfPresent(AIModelIdentity.self, forKey: .identity) ?? .model
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        company = try container.decode(String.self, forKey: .company)
        providerID = AIProviderIdentifier.normalize(
            try container.decodeIfPresent(String.self, forKey: .providerID) ?? company
        )
        price = try container.decodeIfPresent(Int.self, forKey: .price) ?? 0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        supportsSearch = try container.decodeIfPresent(Bool.self, forKey: .supportsSearch) ?? true
        supportsTextGen = try container.decodeIfPresent(Bool.self, forKey: .supportsTextGen) ?? true
        supportsMultimodal = try container.decodeIfPresent(Bool.self, forKey: .supportsMultimodal) ?? false
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        supportReasoningChange = try container.decodeIfPresent(Bool.self, forKey: .supportReasoningChange) ?? false
        supportsImageGen = try container.decodeIfPresent(Bool.self, forKey: .supportsImageGen) ?? false
        supportsVoiceGen = try container.decodeIfPresent(Bool.self, forKey: .supportsVoiceGen) ?? false
        supportsToolUse = try container.decodeIfPresent(Bool.self, forKey: .supportsToolUse) ?? false
        systemProvision = try container.decodeIfPresent(String.self, forKey: .systemProvision) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        briefDescription = try container.decodeIfPresent(String.self, forKey: .briefDescription) ?? ""
        characterDesign = try container.decodeIfPresent(String.self, forKey: .characterDesign) ?? ""
        aiScenarios = try container.decodeIfPresent([String].self, forKey: .aiScenarios) ?? []
        aiToolScenarios = try container.decodeIfPresent([String].self, forKey: .aiToolScenarios) ?? []
        relatedTaskCodes = try container.decodeIfPresent([String].self, forKey: .relatedTaskCodes) ?? []
        baseModelName = try container.decodeIfPresent(String.self, forKey: .baseModelName)
        localFilename = try container.decodeIfPresent(String.self, forKey: .localFilename)
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .source) ?? .system
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    var isLocalModel: Bool {
        providerID == LocalModelService.localProviderID && identity == .model
    }

    var isLocalAgent: Bool {
        providerID == LocalModelService.localProviderID && identity == .agent
    }
}

struct AISearchToolPreferences: Codable, Equatable, Sendable {
    var useKnowledge: Bool
    var knowledgeCount: Int
    var knowledgeSimilarity: Double
    var useSearch: Bool
    var bilingualSearch: Bool
    var searchCount: Int

    init(
        useKnowledge: Bool,
        knowledgeCount: Int,
        knowledgeSimilarity: Double,
        useSearch: Bool,
        bilingualSearch: Bool,
        searchCount: Int
    ) {
        self.useKnowledge = useKnowledge
        self.knowledgeCount = knowledgeCount
        self.knowledgeSimilarity = knowledgeSimilarity
        self.useSearch = useSearch
        self.bilingualSearch = bilingualSearch
        self.searchCount = searchCount
    }

    enum CodingKeys: String, CodingKey {
        case useKnowledge
        case knowledgeCount
        case knowledgeSimilarity
        case useSearch
        case bilingualSearch
        case searchCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useKnowledge = try container.decodeIfPresent(Bool.self, forKey: .useKnowledge) ?? true
        knowledgeCount = try container.decodeIfPresent(Int.self, forKey: .knowledgeCount) ?? 12
        knowledgeSimilarity = try container.decodeIfPresent(Double.self, forKey: .knowledgeSimilarity) ?? 0.55
        useSearch = try container.decodeIfPresent(Bool.self, forKey: .useSearch) ?? true
        bilingualSearch = try container.decodeIfPresent(Bool.self, forKey: .bilingualSearch) ?? true
        searchCount = try container.decodeIfPresent(Int.self, forKey: .searchCount) ?? 8
    }
}

struct PromptRepo: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var isSystem: Bool
    var timestamp: Date
}

struct MemoryArchive: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var pinned: Bool
    var timestamp: Date
}

struct TranslationDic: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var sourceText: String
    var targetText: String
    var note: String
    var timestamp: Date
}

enum AISettingsDefaults {
    static var apiKeys: [APIKeys] {
        let timestamp = Date()
        return [
            APIKeys(
                name: "Spark Default",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/chat/completions",
                isHidden: false,
                help: "Spark first-party endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Spark Embedding",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/embeddings",
                isHidden: false,
                help: "Spark first-party embedding endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Spark TTS",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/audio/speech",
                isHidden: false,
                help: "Spark first-party text-to-speech endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "OpenAI",
                company: "OPENAI",
                key: "",
                requestURL: "https://api.openai.com/v1/chat/completions",
                isHidden: true,
                help: "OpenAI compatible endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Anthropic",
                company: "ANTHROPIC",
                key: "",
                requestURL: "https://api.anthropic.com/v1/messages",
                isHidden: true,
                help: "Claude models endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Google Gemini",
                company: "GOOGLE",
                key: "",
                requestURL: "https://generativelanguage.googleapis.com/v1beta/models",
                isHidden: true,
                help: "Gemini models endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Qwen",
                company: "QWEN",
                key: "",
                requestURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                isHidden: true,
                help: "Qwen compatible endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "DeepSeek",
                company: "DEEPSEEK",
                key: "",
                requestURL: "https://api.deepseek.com/v1/chat/completions",
                isHidden: true,
                help: "DeepSeek official endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Zhipu",
                company: "ZHIPUAI",
                key: "",
                requestURL: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
                isHidden: true,
                help: "GLM model endpoint",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    static var searchKeys: [SearchKeys] {
        let timestamp = Date()
        return [
            SearchKeys(
                name: "Spark Search",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/search",
                isUsing: true,
                searchClass: "web",
                help: "Default web search connector",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "Tavily Search",
                company: "TAVILY",
                key: "",
                requestURL: "https://api.tavily.com/search",
                isUsing: false,
                searchClass: "web",
                help: "High quality web retrieval for RAG",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "SerpAPI",
                company: "SERPAPI",
                key: "",
                requestURL: "https://serpapi.com/search.json",
                isUsing: false,
                searchClass: "web",
                help: "Google/Baidu mixed search API",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    static var toolKeys: [ToolKeys] {
        let timestamp = Date()
        return [
            ToolKeys(
                name: "Spark Tools",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/tools",
                isUsing: true,
                toolClass: "tool",
                help: "Default tool routing endpoint",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "OpenWeatherMap",
                company: "OPENWEATHER",
                key: "",
                requestURL: "https://api.openweathermap.org/data/2.5/weather",
                isUsing: false,
                toolClass: "weather",
                help: "Weather query tool",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "Google Maps",
                company: "GOOGLE",
                key: "",
                requestURL: "https://maps.googleapis.com/maps/api/geocode/json",
                isUsing: false,
                toolClass: "map",
                help: "Map and geocode tool",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "Google Calendar",
                company: "GOOGLE",
                key: "",
                requestURL: "https://www.googleapis.com/calendar/v3",
                isUsing: false,
                toolClass: "calendar",
                help: "Calendar integration tool",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "GitHub Code Search",
                company: "GITHUB",
                key: "",
                requestURL: "https://api.github.com/search/code",
                isUsing: false,
                toolClass: "code",
                help: "Code search tool for repositories",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    static var allModels: [AllModels] {
        let timestamp = Date()
        return [
            AllModels(
                name: "spark-chat-default",
                displayName: "Spark Chat",
                identity: .model,
                position: 1,
                company: "SPARK",
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-medical-extraction",
                displayName: "Spark Medical Extraction",
                identity: .model,
                position: 2,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-embedding-default",
                displayName: "Spark Embedding",
                identity: .model,
                position: 3,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-tts-default",
                displayName: "Spark TTS",
                identity: .model,
                position: 4,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: true,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-optimization-default",
                displayName: "Spark Optimization",
                identity: .model,
                position: 5,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gpt-5",
                displayName: "GPT-5",
                identity: .model,
                position: 10,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gpt-5-mini",
                displayName: "GPT-5 Mini",
                identity: .model,
                position: 11,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "o4-mini",
                displayName: "o4-mini",
                identity: .model,
                position: 12,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "claude-sonnet-4-5",
                displayName: "Claude Sonnet 4.5",
                identity: .model,
                position: 20,
                company: "ANTHROPIC",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "claude-3-7-sonnet",
                displayName: "Claude 3.7 Sonnet",
                identity: .model,
                position: 21,
                company: "ANTHROPIC",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gemini-2.5-pro",
                displayName: "Gemini 2.5 Pro",
                identity: .model,
                position: 30,
                company: "GOOGLE",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gemini-2.5-flash",
                displayName: "Gemini 2.5 Flash",
                identity: .model,
                position: 31,
                company: "GOOGLE",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "qwen3-max",
                displayName: "Qwen3 Max",
                identity: .model,
                position: 40,
                company: "QWEN",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "qwen-plus",
                displayName: "Qwen Plus",
                identity: .model,
                position: 41,
                company: "QWEN",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "deepseek-chat",
                displayName: "DeepSeek Chat",
                identity: .model,
                position: 50,
                company: "DEEPSEEK",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "deepseek-reasoner",
                displayName: "DeepSeek Reasoner",
                identity: .model,
                position: 51,
                company: "DEEPSEEK",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "glm-4.5",
                displayName: "GLM 4.5",
                identity: .model,
                position: 60,
                company: "ZHIPUAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "glm-4.5v",
                displayName: "GLM 4.5V",
                identity: .model,
                position: 61,
                company: "ZHIPUAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "text-embedding-3-large",
                displayName: "Embedding Large",
                identity: .model,
                position: 70,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "text-embedding-3-small",
                displayName: "Embedding Small",
                identity: .model,
                position: 71,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-agent-doctor",
                displayName: "Spark Doctor Agent",
                identity: .agent,
                position: 80,
                company: "SPARK",
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    static var searchToolPreferences: AISearchToolPreferences {
        AISearchToolPreferences(
            useKnowledge: true,
            knowledgeCount: 12,
            knowledgeSimilarity: 0.55,
            useSearch: true,
            bilingualSearch: true,
            searchCount: 8
        )
    }

    static var promptRepo: [PromptRepo] {
        let timestamp = Date()
        return [
            PromptRepo(
                title: "健康助手默认提示词",
                content: "你是一位专业健康助手。回答要分层：先结论，再行动建议，再风险提示；避免绝对化诊断。",
                isSystem: true,
                timestamp: timestamp
            ),
            PromptRepo(
                title: "医学抽取结构化模板",
                content: "从输入文本提取：主诉、现病史、既往史、过敏史、用药史、检查结果、评估与建议。缺失字段返回 null。",
                isSystem: true,
                timestamp: timestamp
            ),
            PromptRepo(
                title: "知识召回增强模板",
                content: "优先使用召回知识回答；若知识不足，明确说明不确定性并给出后续补充信息建议。",
                isSystem: true,
                timestamp: timestamp
            ),
            PromptRepo(
                title: "双语医学解释模板",
                content: "先用中文解释医学术语，再给出英文对应术语和一句简明定义，保持术语一致。",
                isSystem: true,
                timestamp: timestamp
            )
        ]
    }

    static var memoryArchive: [MemoryArchive] {
        []
    }

    static var translationDic: [TranslationDic] {
        let timestamp = Date()
        return [
            TranslationDic(
                sourceText: "HbA1c",
                targetText: "糖化血红蛋白",
                note: "反映近 2-3 个月平均血糖",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "SBP",
                targetText: "收缩压",
                note: "高压",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "DBP",
                targetText: "舒张压",
                note: "低压",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "BMI",
                targetText: "体质指数",
                note: "体重(kg)/身高(m)^2",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "eGFR",
                targetText: "估算肾小球滤过率",
                note: "用于评估肾功能",
                timestamp: timestamp
            )
        ]
    }
}
