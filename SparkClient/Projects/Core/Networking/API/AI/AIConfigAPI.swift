import Foundation

struct SparkAIConfigAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SparkNetworkEngine) {
        self.configuration = SparkBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    func fetchBootstrapPatch(
        platform: String = "ios",
        clientVersion: String? = nil
    ) async throws -> AIRemoteSettingsPatch {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "platform", value: platform)]
        if let clientVersion, clientVersion.isEmpty == false {
            queryItems.append(URLQueryItem(name: "client_version", value: clientVersion))
        }

        let operation = CacheableSparkNetworkOperation(
            name: "AIConfig.Bootstrap",
            apiName: "AIConfigAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/config/bootstrap/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: true,
                    serialKey: "ai.config.bootstrap",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: 60
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(RemoteAIBootstrapPayload.self, from: response)
        return payload.toPatch()
    }
}

struct BackendAIRemoteConfigProvider: AIRemoteConfigProvider, @unchecked Sendable {
    private let api: SparkAIConfigAPI
    private let platform: String
    private let clientVersion: String?

    init(
        api: SparkAIConfigAPI,
        platform: String = "ios",
        clientVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) {
        self.api = api
        self.platform = platform
        self.clientVersion = clientVersion
    }

    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch {
        try await api.fetchBootstrapPatch(platform: platform, clientVersion: clientVersion)
    }
}

private struct RemoteAIBootstrapPayload: Decodable {
    let revision: String?
    let scenarios: RemoteScenarioCollection?
    let apiKeys: [RemoteAPIKeyItem]?
    let searchKeys: [RemoteSearchKeyItem]?
    let toolKeys: [RemoteToolKeyItem]?
    let allModels: [RemoteModelItem]?
    let userInfo: RemoteUserInfoPatch?

    enum CodingKeys: String, CodingKey {
        case revision
        case scenarios
        case apiKeys = "api_keys"
        case searchKeys = "search_keys"
        case toolKeys = "tool_keys"
        case allModels = "all_models"
        case userInfo = "user_info"
    }

    func toPatch(now: Date = Date()) -> AIRemoteSettingsPatch {
        let defaults = AISettingsSnapshot.default
        return AIRemoteSettingsPatch(
            revision: revision,
            chat: scenarios?.chat?.toScenarioConfig(fallback: defaults.chat),
            medicalExtraction: scenarios?.medicalExtraction?.toScenarioConfig(fallback: defaults.medicalExtraction),
            embedding: scenarios?.embedding?.toScenarioConfig(fallback: defaults.embedding),
            apiKeys: apiKeys?.map { $0.toModel(now: now) },
            searchKeys: searchKeys?.map { $0.toModel(now: now) },
            toolKeys: toolKeys?.map { $0.toModel(now: now) },
            allModels: allModels?.map { $0.toModel(now: now) },
            userInfo: userInfo?.toPatch()
        )
    }
}

private struct RemoteScenarioCollection: Decodable {
    let chat: RemoteScenarioConfig?
    let medicalExtraction: RemoteScenarioConfig?
    let embedding: RemoteScenarioConfig?

    enum CodingKeys: String, CodingKey {
        case chat
        case medicalExtraction = "medical_extraction"
        case embedding
    }
}

private struct RemoteScenarioConfig: Decodable {
    let endpoint: String?
    let model: String?
    let apiKey: String?
    let temperature: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case apiKey = "api_key"
        case temperature
        case maxTokens = "max_tokens"
    }

    func toScenarioConfig(fallback: AIScenarioConfig) -> AIScenarioConfig {
        AIScenarioConfig(
            endpoint: endpoint ?? fallback.endpoint,
            model: model ?? fallback.model,
            apiKey: apiKey ?? fallback.apiKey,
            temperature: temperature ?? fallback.temperature,
            maxTokens: maxTokens ?? fallback.maxTokens
        )
    }
}

private struct RemoteAPIKeyItem: Decodable {
    let name: String
    let company: String
    let key: String?
    let requestURL: String
    let isHidden: Bool?
    let help: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case key
        case requestURL = "request_url"
        case isHidden = "is_hidden"
        case help
        case source
    }

    func toModel(now: Date) -> APIKeys {
        APIKeys(
            name: name,
            company: company,
            key: key ?? "",
            requestURL: requestURL,
            isHidden: isHidden ?? false,
            help: help ?? "",
            source: AIRecordSource(rawValue: source ?? "") ?? .system,
            timestamp: now
        )
    }
}

private struct RemoteSearchKeyItem: Decodable {
    let name: String
    let company: String
    let key: String?
    let requestURL: String
    let isUsing: Bool?
    let searchClass: String?
    let help: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case key
        case requestURL = "request_url"
        case isUsing = "is_using"
        case searchClass = "search_class"
        case help
        case source
    }

    func toModel(now: Date) -> SearchKeys {
        SearchKeys(
            name: name,
            company: company,
            key: key ?? "",
            requestURL: requestURL,
            isUsing: isUsing ?? false,
            searchClass: searchClass ?? "web",
            help: help ?? "",
            source: AIRecordSource(rawValue: source ?? "") ?? .system,
            timestamp: now
        )
    }
}

private struct RemoteToolKeyItem: Decodable {
    let name: String
    let company: String
    let key: String?
    let requestURL: String
    let isUsing: Bool?
    let toolClass: String?
    let help: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case key
        case requestURL = "request_url"
        case isUsing = "is_using"
        case toolClass = "tool_class"
        case help
        case source
    }

    func toModel(now: Date) -> ToolKeys {
        ToolKeys(
            name: name,
            company: company,
            key: key ?? "",
            requestURL: requestURL,
            isUsing: isUsing ?? false,
            toolClass: toolClass ?? "native",
            help: help ?? "",
            source: AIRecordSource(rawValue: source ?? "") ?? .system,
            timestamp: now
        )
    }
}

private struct RemoteModelItem: Decodable {
    let name: String
    let displayName: String?
    let identity: String?
    let position: Int?
    let company: String
    let isHidden: Bool?
    let supportsSearch: Bool?
    let supportsMultimodal: Bool?
    let supportsReasoning: Bool?
    let supportsToolUse: Bool?
    let supportsVoiceGen: Bool?
    let supportsImageGen: Bool?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case identity
        case position
        case company
        case isHidden = "is_hidden"
        case supportsSearch = "supports_search"
        case supportsMultimodal = "supports_multimodal"
        case supportsReasoning = "supports_reasoning"
        case supportsToolUse = "supports_tool_use"
        case supportsVoiceGen = "supports_voice_gen"
        case supportsImageGen = "supports_image_gen"
        case source
    }

    func toModel(now: Date) -> AllModels {
        AllModels(
            name: name,
            displayName: displayName ?? name,
            identity: AIModelIdentity(rawValue: identity ?? "") ?? .model,
            position: position ?? 0,
            company: company,
            isHidden: isHidden ?? false,
            supportsSearch: supportsSearch ?? false,
            supportsMultimodal: supportsMultimodal ?? false,
            supportsReasoning: supportsReasoning ?? false,
            supportsToolUse: supportsToolUse ?? false,
            supportsVoiceGen: supportsVoiceGen ?? false,
            supportsImageGen: supportsImageGen ?? false,
            source: AIRecordSource(rawValue: source ?? "") ?? .system,
            timestamp: now
        )
    }
}

private struct RemoteUserInfoPatch: Decodable {
    let chooseEmbeddingModel: String?
    let optimizationTextModel: String?
    let optimizationVisualModel: String?
    let textToSpeechModel: String?
    let useKnowledge: Bool?
    let knowledgeCount: Int?
    let knowledgeSimilarity: Double?
    let useSearch: Bool?
    let bilingualSearch: Bool?
    let searchCount: Int?
    let useMap: Bool?
    let useCalendar: Bool?
    let useWeather: Bool?
    let useCanvas: Bool?
    let useCode: Bool?

    enum CodingKeys: String, CodingKey {
        case chooseEmbeddingModel = "choose_embedding_model"
        case optimizationTextModel = "optimization_text_model"
        case optimizationVisualModel = "optimization_visual_model"
        case textToSpeechModel = "text_to_speech_model"
        case useKnowledge = "use_knowledge"
        case knowledgeCount = "knowledge_count"
        case knowledgeSimilarity = "knowledge_similarity"
        case useSearch = "use_search"
        case bilingualSearch = "bilingual_search"
        case searchCount = "search_count"
        case useMap = "use_map"
        case useCalendar = "use_calendar"
        case useWeather = "use_weather"
        case useCanvas = "use_canvas"
        case useCode = "use_code"
    }

    func toPatch() -> AIRemoteUserInfoPatch {
        AIRemoteUserInfoPatch(
            chooseEmbeddingModel: chooseEmbeddingModel,
            optimizationTextModel: optimizationTextModel,
            optimizationVisualModel: optimizationVisualModel,
            textToSpeechModel: textToSpeechModel,
            useKnowledge: useKnowledge,
            knowledgeCount: knowledgeCount,
            knowledgeSimilarity: knowledgeSimilarity,
            useSearch: useSearch,
            bilingualSearch: bilingualSearch,
            searchCount: searchCount,
            useMap: useMap,
            useCalendar: useCalendar,
            useWeather: useWeather,
            useCanvas: useCanvas,
            useCode: useCode
        )
    }
}
