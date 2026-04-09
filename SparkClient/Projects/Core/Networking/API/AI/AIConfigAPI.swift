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
                    requiresAuth: true,
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

    func fetchTrialStatus() async throws -> AITrialState {
        let operation = CacheableSparkNetworkOperation(
            name: "AIConfig.TrialStatus",
            apiName: "AIConfigAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/ai/trial/status/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.trial.status",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(RemoteTrialStatusPayload.self, from: response)
        return payload.toModel()
    }

    func applyTrial(note: String = "") async throws -> AITrialState {
        struct ApplyTrialBody: Encodable {
            let note: String
        }
        let operation = CacheableSparkNetworkOperation(
            name: "AIConfig.TrialApply",
            apiName: "AIConfigAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/trial/apply/",
                body: .json(AnyEncodable(ApplyTrialBody(note: note))),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.trial.apply",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(RemoteTrialStatusPayload.self, from: response)
        return payload.toModel()
    }

    func testProviderConnection(requestURL: String, apiKey: String, model: String) async throws -> Bool {
        struct TestProviderBody: Encodable {
            let request_url: String
            let api_key: String
            let model: String
        }
        let operation = CacheableSparkNetworkOperation(
            name: "AIConfig.ProviderConnectionTest",
            apiName: "AIConfigAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/ai/providers/test-connection/",
                body: .json(
                    AnyEncodable(
                        TestProviderBody(
                            request_url: requestURL,
                            api_key: apiKey,
                            model: model
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ai.provider.test_connection",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(RemoteProviderTestPayload.self, from: response)
        return payload.reachable
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
    let trial: RemoteTrialState?
    let trialModelPolicy: [RemoteTrialModelPolicyItem]?

    enum CodingKeys: String, CodingKey {
        case revision
        case scenarios
        case apiKeys = "api_keys"
        case searchKeys = "search_keys"
        case toolKeys = "tool_keys"
        case allModels = "all_models"
        case userInfo = "user_info"
        case trial
        case trialModelPolicy = "trial_model_policy"
    }

    func toPatch(now: Date = Date()) -> AIRemoteSettingsPatch {
        let defaults = AISettingsSnapshot.default
        if let scenarios {
            let bundles = scenarios.asCollection(fallback: defaults)
            func materialize(_ bundle: AIScenarioRemoteBundle) -> AIScenarioConfig? {
                bundle.resolveRow(preferredModelName: nil)?.asScenarioConfig()
            }
            return AIRemoteSettingsPatch(
                revision: revision,
                scenarioRemoteBundles: bundles,
                chat: materialize(bundles.chat),
                optimizationText: materialize(bundles.optimizationText),
                optimizationVisual: materialize(bundles.optimizationVisual),
                contextFolding: materialize(bundles.contextFolding),
                router: materialize(bundles.router),
                modelConfig: materialize(bundles.modelConfig),
                reportInterpretation: materialize(bundles.reportInterpretation),
                apiKeys: apiKeys?.map { $0.toModel(now: now) },
                searchKeys: searchKeys?.map { $0.toModel(now: now) },
                toolKeys: toolKeys?.map { $0.toModel(now: now) },
                allModels: allModels?.map { $0.toModel(now: now) },
                userInfo: userInfo?.toPatch(),
                trial: trial?.toModel(),
                trialModelPolicy: trialModelPolicy?.compactMap { $0.toModel(fallbackSnapshot: defaults) }
            )
        }
        return AIRemoteSettingsPatch(
            revision: revision,
            scenarioRemoteBundles: nil,
            chat: nil,
            optimizationText: nil,
            optimizationVisual: nil,
            contextFolding: nil,
            router: nil,
            modelConfig: nil,
            reportInterpretation: nil,
            apiKeys: apiKeys?.map { $0.toModel(now: now) },
            searchKeys: searchKeys?.map { $0.toModel(now: now) },
            toolKeys: toolKeys?.map { $0.toModel(now: now) },
            allModels: allModels?.map { $0.toModel(now: now) },
            userInfo: userInfo?.toPatch(),
            trial: trial?.toModel(),
            trialModelPolicy: trialModelPolicy?.compactMap { $0.toModel(fallbackSnapshot: defaults) }
        )
    }
}

private struct RemoteScenarioCollection: Decodable {
    let chat: AIScenarioRemoteBundle?
    let medicalStructuredExtraction: AIScenarioRemoteBundle?
    let medicalDocumentTypeRecognition: AIScenarioRemoteBundle?
    let medicalCaseExtraction: AIScenarioRemoteBundle?
    let healthExamExtraction: AIScenarioRemoteBundle?
    let medicalReportExtraction: AIScenarioRemoteBundle?
    let prescriptionExtraction: AIScenarioRemoteBundle?
    let medicationExtraction: AIScenarioRemoteBundle?
    let optimizationText: AIScenarioRemoteBundle?
    let optimizationVisual: AIScenarioRemoteBundle?
    let contextFolding: AIScenarioRemoteBundle?
    let router: AIScenarioRemoteBundle?
    let modelConfig: AIScenarioRemoteBundle?
    let reportInterpretation: AIScenarioRemoteBundle?

    enum CodingKeys: String, CodingKey {
        case chat
        case medicalStructuredExtraction = "medical_structured_extraction"
        case medicalDocumentTypeRecognition = "medical_document_type_recognition"
        case medicalCaseExtraction = "medical_case_extraction"
        case healthExamExtraction = "health_exam_extraction"
        case medicalReportExtraction = "medical_report_extraction"
        case prescriptionExtraction = "prescription_extraction"
        case medicationExtraction = "medication_extraction"
        case optimizationText = "optimization_text"
        case optimizationVisual = "optimization_visual"
        case contextFolding = "context_folding"
        case router
        case modelConfig = "model_config"
        case reportInterpretation = "report_interpretation"
    }

    func asCollection(fallback: AISettingsSnapshot) -> AIScenarioRemoteBundlesCollection {
        AIScenarioRemoteBundlesCollection(
            chat: chat ?? .singleModelFallback(fallback.chat),
            medicalStructuredExtraction: medicalStructuredExtraction ?? .singleModelFallback(fallback.optimizationText),
            medicalDocumentTypeRecognition: medicalDocumentTypeRecognition ?? .singleModelFallback(fallback.optimizationText),
            medicalCaseExtraction: medicalCaseExtraction ?? .singleModelFallback(fallback.optimizationText),
            healthExamExtraction: healthExamExtraction ?? .singleModelFallback(fallback.optimizationText),
            medicalReportExtraction: medicalReportExtraction ?? .singleModelFallback(fallback.optimizationText),
            prescriptionExtraction: prescriptionExtraction ?? .singleModelFallback(fallback.optimizationText),
            medicationExtraction: medicationExtraction ?? .singleModelFallback(fallback.optimizationText),
            optimizationText: optimizationText ?? .singleModelFallback(fallback.optimizationText),
            optimizationVisual: optimizationVisual ?? .singleModelFallback(fallback.optimizationVisual),
            contextFolding: contextFolding ?? .singleModelFallback(fallback.contextFolding),
            router: router ?? .singleModelFallback(fallback.router),
            modelConfig: modelConfig ?? .singleModelFallback(fallback.modelConfig),
            reportInterpretation: reportInterpretation ?? .singleModelFallback(fallback.reportInterpretation)
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
    let privacyPolicyURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case key
        case requestURL = "request_url"
        case isHidden = "is_hidden"
        case help
        case source
        case privacyPolicyURL = "privacy_policy_url"
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
            privacyPolicyURL: privacyPolicyURL ?? "",
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
    let position: Int?
    let company: String
    let isHidden: Bool?
    let supportsSearch: Bool?
    let supportsMultimodal: Bool?
    let supportsReasoning: Bool?
    let supportsToolUse: Bool?
    let supportsVoiceGen: Bool?
    let supportsImageGen: Bool?
    let priceTier: Int?
    let supportsText: Bool?
    let reasoningControllable: Bool?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case position
        case company
        case isHidden = "is_hidden"
        case supportsSearch = "supports_search"
        case supportsMultimodal = "supports_multimodal"
        case supportsReasoning = "supports_reasoning"
        case supportsToolUse = "supports_tool_use"
        case supportsVoiceGen = "supports_voice_gen"
        case supportsImageGen = "supports_image_gen"
        case priceTier = "price_tier"
        case supportsText = "supports_text"
        case reasoningControllable = "reasoning_controllable"
        case source
    }

    func toModel(now: Date) -> AllModels {
        let tier = priceTier.map { min(max($0, 0), 3) } ?? 0
        return AllModels(
            name: name,
            displayName: displayName ?? name,
            identity: .model,
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
            timestamp: now,
            priceTier: tier,
            supportsText: supportsText ?? true,
            reasoningControllable: reasoningControllable ?? false
        )
    }
}

private struct RemoteUserInfoPatch: Decodable {
    let chooseEmbeddingModel: String?
    let optimizationTextModel: String?
    let optimizationVisualModel: String?
    let contextFoldingModel: String?
    let routerModel: String?
    let dataExtractionModel: String?
    let reportInterpretationModel: String?
    let textToSpeechModel: String?
    let useContextFolding: Bool?
    let maxToolSets: Int?
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
        case contextFoldingModel = "context_folding_model"
        case routerModel = "router_model"
        case dataExtractionModel = "data_extraction_model"
        case reportInterpretationModel = "report_interpretation_model"
        case textToSpeechModel = "text_to_speech_model"
        case useContextFolding = "use_context_folding"
        case maxToolSets = "max_tool_sets"
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
            contextFoldingModel: contextFoldingModel,
            routerModel: routerModel,
            dataExtractionModel: dataExtractionModel,
            reportInterpretationModel: reportInterpretationModel,
            textToSpeechModel: textToSpeechModel,
            useContextFolding: useContextFolding,
            maxToolSets: maxToolSets,
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

private struct RemoteTrialState: Decodable {
    let status: String?
    let isActive: Bool?
    let grantSource: String?
    let startedAt: String?
    let expiresAt: String?
    let remainingSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case isActive = "is_active"
        case grantSource = "grant_source"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
    }

    func toModel() -> AITrialState {
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ value: String?) -> Date? {
            guard let value else { return nil }
            return fractionalFormatter.date(from: value) ?? formatter.date(from: value)
        }

        return AITrialState(
            status: status ?? AITrialState.inactive.status,
            isActive: isActive ?? false,
            grantSource: grantSource ?? AITrialState.inactive.grantSource,
            startedAt: parseDate(startedAt),
            expiresAt: parseDate(expiresAt),
            remainingSeconds: remainingSeconds ?? 0
        )
    }
}

private struct RemoteTrialStatusPayload: Decodable {
    let status: String?
    let isActive: Bool?
    let grantSource: String?
    let startedAt: String?
    let expiresAt: String?
    let remainingSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case isActive = "is_active"
        case grantSource = "grant_source"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
    }

    func toModel() -> AITrialState {
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ value: String?) -> Date? {
            guard let value else { return nil }
            return fractionalFormatter.date(from: value) ?? formatter.date(from: value)
        }

        return AITrialState(
            status: status ?? AITrialState.inactive.status,
            isActive: isActive ?? false,
            grantSource: grantSource ?? AITrialState.inactive.grantSource,
            startedAt: parseDate(startedAt),
            expiresAt: parseDate(expiresAt),
            remainingSeconds: remainingSeconds ?? 0
        )
    }
}

private struct RemoteProviderTestPayload: Decodable {
    let reachable: Bool
}

private struct RemoteTrialModelPolicyItem: Decodable {
    let scenario: String?
    let endpoint: String?
    let model: String?
    let apiKey: String?
    let temperature: Double?
    let maxTokens: Int?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case scenario
        case endpoint
        case model
        case apiKey = "api_key"
        case temperature
        case maxTokens = "max_tokens"
        case isDefault = "is_default"
    }

    func toModel(fallbackSnapshot: AISettingsSnapshot) -> AITrialModelPolicyItem? {
        guard
            let rawScenario = scenario,
            let typedScenario = decodeScenario(rawScenario)
        else {
            return nil
        }

        let fallback = fallbackSnapshot.config(for: typedScenario)
        let scenarioConfig = AIScenarioConfig(
            endpoint: endpoint ?? fallback.endpoint,
            model: model ?? fallback.model,
            apiKey: apiKey ?? fallback.apiKey,
            temperature: temperature ?? fallback.temperature,
            maxTokens: maxTokens ?? fallback.maxTokens
        )
        return AITrialModelPolicyItem(
            scenario: typedScenario,
            config: scenarioConfig,
            isDefault: isDefault ?? false
        )
    }

    private func decodeScenario(_ raw: String) -> AIScenario? {
        AIScenario(rawValue: raw)
    }
}
