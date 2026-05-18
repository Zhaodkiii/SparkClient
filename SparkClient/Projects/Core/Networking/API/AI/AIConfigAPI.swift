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

    func testProviderConnection(requestURL: String, apiKey: String, model: String) async throws -> ProviderConnectionTestResult {
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
        return try APIResponseDecoder.decodeWrappedData(ProviderConnectionTestResult.self, from: response)
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
    let smallTasks: [SmallTask]?

    func toPatch() -> AIRemoteSettingsPatch {
        let smallTasks = smallTasks ?? []
        guard let scenarios else {
            return AIRemoteSettingsPatch(revision: revision, scenarioRemoteBundles: nil, smallTasks: smallTasks)
        }
        return AIRemoteSettingsPatch(
            revision: revision,
            scenarioRemoteBundles: scenarios.asProScenarioCollection(),
            smallTasks: smallTasks
        )
    }
}

private struct RemoteScenarioCollection: Decodable {
    let chat: AIScenarioRemoteBundle?
    let embedding: AIScenarioRemoteBundle?
    let voice: AIScenarioRemoteBundle?
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


    /// Pro bootstrap 可能只返回部分场景；未出现的场景用空包占位（合并时由运行时逻辑回退到本地包）。
    /// 所有模型统一标记 source 为 `.pro`，以区别于本地模型（`system`/`custom`）。
    func asProScenarioCollection() -> AIScenarioRemoteBundlesCollection {
        let empty = AIScenarioRemoteBundle(defaultModelName: "", models: [])
        return AIScenarioRemoteBundlesCollection(
            chat: markPro(chat) ?? empty,
            embedding: markPro(embedding) ?? empty,
            voice: markPro(voice) ?? empty,
            medicalStructuredExtraction: markPro(medicalStructuredExtraction) ?? empty,
            medicalDocumentTypeRecognition: markPro(medicalDocumentTypeRecognition) ?? empty,
            medicalCaseExtraction: markPro(medicalCaseExtraction) ?? empty,
            healthExamExtraction: markPro(healthExamExtraction) ?? empty,
            medicalReportExtraction: markPro(medicalReportExtraction) ?? empty,
            prescriptionExtraction: markPro(prescriptionExtraction) ?? empty,
            medicationExtraction: markPro(medicationExtraction) ?? empty,
            optimizationText: markPro(optimizationText) ?? empty,
            optimizationVisual: markPro(optimizationVisual) ?? empty,
            contextFolding: markPro(contextFolding) ?? empty,
            router: markPro(router) ?? empty,
            modelConfig: markPro(modelConfig) ?? empty,
            reportInterpretation: markPro(reportInterpretation) ?? empty
        )
    }

    /// 将 bundle 内所有模型的 source 统一标记为 Pro；若 bundle 为 nil 则返回 nil。
    private func markPro(_ bundle: AIScenarioRemoteBundle?) -> AIScenarioRemoteBundle? {
        guard let bundle else { return nil }
        let proSource = AIRecordSource.pro.rawValue
        let markedModels = bundle.models.map { row -> AIScenarioRemoteModelRow in
            var m = row
            m.source = proSource
            return m
        }
        return AIScenarioRemoteBundle(defaultModelName: bundle.defaultModelName, models: markedModels)
    }
}

// MARK: - Trial Status API Models

private struct RemoteTrialStatusPayload: Decodable {
    let status: String?
    let isActive: Bool?
    let grantSource: String?
    let startedAt: String?
    let expiresAt: String?
    let remainingSeconds: Int?


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

// MARK: - Provider Test API Models

struct ProviderConnectionTestResult: Decodable, Sendable {
    let reachable: Bool
    let message: String?
}
