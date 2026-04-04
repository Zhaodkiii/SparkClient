import Foundation

enum AIRecordSource: String, Codable, CaseIterable, Sendable {
    case system
    case custom
}

enum AIModelIdentity: String, Codable, CaseIterable, Sendable {
    case model
    case agent
}

enum AIModelSelectionSource: String, Codable, CaseIterable, Sendable {
    case localKey
    case trial
}

struct APIKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isHidden: Bool
    var help: String
    var source: AIRecordSource
    var privacyPolicyURL: String
    var privacyPolicyAccepted: Bool
    var privacyPolicyAcceptedAt: Date?
    var timestamp: Date

    init(
        id: UUID = UUID(),
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
        timestamp: Date
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.isHidden = isHidden
        self.help = help
        self.source = source
        self.privacyPolicyURL = privacyPolicyURL
        self.privacyPolicyAccepted = privacyPolicyAccepted
        self.privacyPolicyAcceptedAt = privacyPolicyAcceptedAt
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case company
        case key
        case requestURL
        case isHidden
        case help
        case source
        case privacyPolicyURL
        case privacyPolicyAccepted
        case privacyPolicyAcceptedAt
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        requestURL = try container.decodeIfPresent(String.self, forKey: .requestURL) ?? ""
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? true
        help = try container.decodeIfPresent(String.self, forKey: .help) ?? ""
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .source) ?? .system
        privacyPolicyURL = try container.decodeIfPresent(String.self, forKey: .privacyPolicyURL) ?? ""
        privacyPolicyAccepted = try container.decodeIfPresent(Bool.self, forKey: .privacyPolicyAccepted) ?? false
        privacyPolicyAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .privacyPolicyAcceptedAt)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(company, forKey: .company)
        try container.encode(key, forKey: .key)
        try container.encode(requestURL, forKey: .requestURL)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(help, forKey: .help)
        try container.encode(source, forKey: .source)
        try container.encode(privacyPolicyURL, forKey: .privacyPolicyURL)
        try container.encode(privacyPolicyAccepted, forKey: .privacyPolicyAccepted)
        try container.encodeIfPresent(privacyPolicyAcceptedAt, forKey: .privacyPolicyAcceptedAt)
        try container.encode(timestamp, forKey: .timestamp)
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
    var company: String
    var isHidden: Bool
    var supportsSearch: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportsToolUse: Bool
    var supportsVoiceGen: Bool
    var supportsImageGen: Bool
    /// 0 免费，1 经济，2 标准，3 高级
    var priceTier: Int
    var supportsText: Bool
    var reasoningControllable: Bool
    var iconSymbol: String?
    var baseModelName: String?
    var localFilename: String?
    var systemPrompt: String?
    var source: AIRecordSource
    var timestamp: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
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
        timestamp: Date,
        priceTier: Int = 0,
        supportsText: Bool = true,
        reasoningControllable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.position = position
        self.company = company
        self.isHidden = isHidden
        self.supportsSearch = supportsSearch
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportsToolUse = supportsToolUse
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsImageGen = supportsImageGen
        self.priceTier = min(max(priceTier, 0), 3)
        self.supportsText = supportsText
        self.reasoningControllable = reasoningControllable
        self.iconSymbol = iconSymbol
        self.baseModelName = baseModelName
        self.localFilename = localFilename
        self.systemPrompt = systemPrompt
        self.source = source
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case identity
        case position
        case company
        case isHidden
        case supportsSearch
        case supportsMultimodal
        case supportsReasoning
        case supportsToolUse
        case supportsVoiceGen
        case supportsImageGen
        case priceTier
        case supportsText
        case reasoningControllable
        case iconSymbol
        case baseModelName
        case localFilename
        case systemPrompt
        case source
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? name
        identity = try container.decodeIfPresent(AIModelIdentity.self, forKey: .identity) ?? .model
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        supportsSearch = try container.decodeIfPresent(Bool.self, forKey: .supportsSearch) ?? false
        supportsMultimodal = try container.decodeIfPresent(Bool.self, forKey: .supportsMultimodal) ?? false
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        supportsToolUse = try container.decodeIfPresent(Bool.self, forKey: .supportsToolUse) ?? false
        supportsVoiceGen = try container.decodeIfPresent(Bool.self, forKey: .supportsVoiceGen) ?? false
        supportsImageGen = try container.decodeIfPresent(Bool.self, forKey: .supportsImageGen) ?? false
        if let tier = try container.decodeIfPresent(Int.self, forKey: .priceTier) {
            priceTier = min(max(tier, 0), 3)
        } else {
            priceTier = 0
        }
        supportsText = try container.decodeIfPresent(Bool.self, forKey: .supportsText) ?? true
        reasoningControllable = try container.decodeIfPresent(Bool.self, forKey: .reasoningControllable) ?? false
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        baseModelName = try container.decodeIfPresent(String.self, forKey: .baseModelName)
        localFilename = try container.decodeIfPresent(String.self, forKey: .localFilename)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .source) ?? .system
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    var isLocalModel: Bool {
        company.uppercased() == LocalModelService.localCompany && identity == .model
    }

    var isLocalAgent: Bool {
        company.uppercased() == LocalModelService.localCompany && identity == .agent
    }
}

struct UserInfo: Codable, Equatable, Sendable {
    var name: String
    var userInfo: String
    var userRequirements: String
    var chooseEmbeddingModel: String
    var optimizationTextModel: String
    var optimizationVisualModel: String
    var contextFoldingModel: String
    var routerModel: String
    var dataExtractionModel: String
    var reportInterpretationModel: String
    var optimizationTextSource: AIModelSelectionSource
    var optimizationVisualSource: AIModelSelectionSource
    var contextFoldingSource: AIModelSelectionSource
    var routerSource: AIModelSelectionSource
    var dataExtractionSource: AIModelSelectionSource
    var reportInterpretationSource: AIModelSelectionSource
    var useContextFolding: Bool
    var maxToolSets: Int
    var textToSpeechModel: String
    var useMemory: Bool
    var useCrossMemory: Bool
    var useHealth: Bool
    var useKnowledge: Bool
    var knowledgeCount: Int
    var knowledgeSimilarity: Double
    var useSearch: Bool
    var bilingualSearch: Bool
    var searchCount: Int
    var useMap: Bool
    var useCalendar: Bool
    var useWeather: Bool
    var useCanvas: Bool
    var useCode: Bool
    var timestamp: Date

    init(
        name: String,
        userInfo: String,
        userRequirements: String,
        chooseEmbeddingModel: String,
        optimizationTextModel: String,
        optimizationVisualModel: String,
        contextFoldingModel: String,
        routerModel: String,
        dataExtractionModel: String,
        reportInterpretationModel: String,
        optimizationTextSource: AIModelSelectionSource,
        optimizationVisualSource: AIModelSelectionSource,
        contextFoldingSource: AIModelSelectionSource,
        routerSource: AIModelSelectionSource,
        dataExtractionSource: AIModelSelectionSource,
        reportInterpretationSource: AIModelSelectionSource,
        useContextFolding: Bool,
        maxToolSets: Int,
        textToSpeechModel: String,
        useMemory: Bool,
        useCrossMemory: Bool,
        useHealth: Bool,
        useKnowledge: Bool,
        knowledgeCount: Int,
        knowledgeSimilarity: Double,
        useSearch: Bool,
        bilingualSearch: Bool,
        searchCount: Int,
        useMap: Bool,
        useCalendar: Bool,
        useWeather: Bool,
        useCanvas: Bool,
        useCode: Bool,
        timestamp: Date
    ) {
        self.name = name
        self.userInfo = userInfo
        self.userRequirements = userRequirements
        self.chooseEmbeddingModel = chooseEmbeddingModel
        self.optimizationTextModel = optimizationTextModel
        self.optimizationVisualModel = optimizationVisualModel
        self.contextFoldingModel = contextFoldingModel
        self.routerModel = routerModel
        self.dataExtractionModel = dataExtractionModel
        self.reportInterpretationModel = reportInterpretationModel
        self.optimizationTextSource = optimizationTextSource
        self.optimizationVisualSource = optimizationVisualSource
        self.contextFoldingSource = contextFoldingSource
        self.routerSource = routerSource
        self.dataExtractionSource = dataExtractionSource
        self.reportInterpretationSource = reportInterpretationSource
        self.useContextFolding = useContextFolding
        self.maxToolSets = maxToolSets
        self.textToSpeechModel = textToSpeechModel
        self.useMemory = useMemory
        self.useCrossMemory = useCrossMemory
        self.useHealth = useHealth
        self.useKnowledge = useKnowledge
        self.knowledgeCount = knowledgeCount
        self.knowledgeSimilarity = knowledgeSimilarity
        self.useSearch = useSearch
        self.bilingualSearch = bilingualSearch
        self.searchCount = searchCount
        self.useMap = useMap
        self.useCalendar = useCalendar
        self.useWeather = useWeather
        self.useCanvas = useCanvas
        self.useCode = useCode
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case name
        case userInfo
        case userRequirements
        case chooseEmbeddingModel
        case optimizationTextModel
        case optimizationVisualModel
        case contextFoldingModel
        case routerModel
        case dataExtractionModel
        case reportInterpretationModel
        case optimizationTextSource
        case optimizationVisualSource
        case contextFoldingSource
        case routerSource
        case dataExtractionSource
        case reportInterpretationSource
        case useContextFolding
        case maxToolSets
        case textToSpeechModel
        case useMemory
        case useCrossMemory
        case useHealth
        case useKnowledge
        case knowledgeCount
        case knowledgeSimilarity
        case useSearch
        case bilingualSearch
        case searchCount
        case useMap
        case useCalendar
        case useWeather
        case useCanvas
        case useCode
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        userInfo = try container.decodeIfPresent(String.self, forKey: .userInfo) ?? ""
        userRequirements = try container.decodeIfPresent(String.self, forKey: .userRequirements) ?? ""
        chooseEmbeddingModel = try container.decodeIfPresent(String.self, forKey: .chooseEmbeddingModel) ?? "spark-embedding-default"
        optimizationTextModel = try container.decodeIfPresent(String.self, forKey: .optimizationTextModel) ?? "spark-optimization-default"
        optimizationVisualModel = try container.decodeIfPresent(String.self, forKey: .optimizationVisualModel) ?? "spark-optimization-default"
        contextFoldingModel = try container.decodeIfPresent(String.self, forKey: .contextFoldingModel) ?? "spark-optimization-default"
        routerModel = try container.decodeIfPresent(String.self, forKey: .routerModel) ?? "spark-chat-default"
        dataExtractionModel = try container.decodeIfPresent(String.self, forKey: .dataExtractionModel) ?? "spark-medical-extraction"
        reportInterpretationModel = try container.decodeIfPresent(String.self, forKey: .reportInterpretationModel) ?? "spark-chat-default"
        let optimizationTextSourceRaw = try container.decodeIfPresent(String.self, forKey: .optimizationTextSource)
        optimizationTextSource = AIModelSelectionSource(rawValue: optimizationTextSourceRaw ?? "") ?? .localKey
        let optimizationVisualSourceRaw = try container.decodeIfPresent(String.self, forKey: .optimizationVisualSource)
        optimizationVisualSource = AIModelSelectionSource(rawValue: optimizationVisualSourceRaw ?? "") ?? .localKey
        let contextFoldingSourceRaw = try container.decodeIfPresent(String.self, forKey: .contextFoldingSource)
        contextFoldingSource = AIModelSelectionSource(rawValue: contextFoldingSourceRaw ?? "") ?? .localKey
        let routerSourceRaw = try container.decodeIfPresent(String.self, forKey: .routerSource)
        routerSource = AIModelSelectionSource(rawValue: routerSourceRaw ?? "") ?? .localKey
        let dataExtractionSourceRaw = try container.decodeIfPresent(String.self, forKey: .dataExtractionSource)
        dataExtractionSource = AIModelSelectionSource(rawValue: dataExtractionSourceRaw ?? "") ?? .localKey
        let reportInterpretationSourceRaw = try container.decodeIfPresent(String.self, forKey: .reportInterpretationSource)
        reportInterpretationSource = AIModelSelectionSource(rawValue: reportInterpretationSourceRaw ?? "") ?? .localKey
        useContextFolding = try container.decodeIfPresent(Bool.self, forKey: .useContextFolding) ?? true
        maxToolSets = try container.decodeIfPresent(Int.self, forKey: .maxToolSets) ?? 3
        textToSpeechModel = try container.decodeIfPresent(String.self, forKey: .textToSpeechModel) ?? "spark-tts-default"
        useMemory = try container.decodeIfPresent(Bool.self, forKey: .useMemory) ?? true
        useCrossMemory = try container.decodeIfPresent(Bool.self, forKey: .useCrossMemory) ?? true
        useHealth = try container.decodeIfPresent(Bool.self, forKey: .useHealth) ?? true
        useKnowledge = try container.decodeIfPresent(Bool.self, forKey: .useKnowledge) ?? true
        knowledgeCount = try container.decodeIfPresent(Int.self, forKey: .knowledgeCount) ?? 12
        knowledgeSimilarity = try container.decodeIfPresent(Double.self, forKey: .knowledgeSimilarity) ?? 0.55
        useSearch = try container.decodeIfPresent(Bool.self, forKey: .useSearch) ?? true
        bilingualSearch = try container.decodeIfPresent(Bool.self, forKey: .bilingualSearch) ?? true
        searchCount = try container.decodeIfPresent(Int.self, forKey: .searchCount) ?? 8
        useMap = try container.decodeIfPresent(Bool.self, forKey: .useMap) ?? true
        useCalendar = try container.decodeIfPresent(Bool.self, forKey: .useCalendar) ?? true
        useWeather = try container.decodeIfPresent(Bool.self, forKey: .useWeather) ?? true
        useCanvas = try container.decodeIfPresent(Bool.self, forKey: .useCanvas) ?? true
        useCode = try container.decodeIfPresent(Bool.self, forKey: .useCode) ?? true
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
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

    static var userInfo: UserInfo {
        UserInfo(
            name: "",
            userInfo: "",
            userRequirements: "",
            chooseEmbeddingModel: "spark-embedding-default",
            optimizationTextModel: "spark-optimization-default",
            optimizationVisualModel: "spark-optimization-default",
            contextFoldingModel: "spark-optimization-default",
            routerModel: "spark-chat-default",
            dataExtractionModel: "spark-medical-extraction",
            reportInterpretationModel: "spark-chat-default",
            optimizationTextSource: .localKey,
            optimizationVisualSource: .localKey,
            contextFoldingSource: .localKey,
            routerSource: .localKey,
            dataExtractionSource: .localKey,
            reportInterpretationSource: .localKey,
            useContextFolding: true,
            maxToolSets: 3,
            textToSpeechModel: "spark-tts-default",
            useMemory: true,
            useCrossMemory: true,
            useHealth: true,
            useKnowledge: true,
            knowledgeCount: 12,
            knowledgeSimilarity: 0.55,
            useSearch: true,
            bilingualSearch: true,
            searchCount: 8,
            useMap: true,
            useCalendar: true,
            useWeather: true,
            useCanvas: true,
            useCode: true,
            timestamp: Date()
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
