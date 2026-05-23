#if canImport(XCTest)
import XCTest

final class AISettingsAndResolverTests: XCTestCase {
    func testScenarioResolverPrefersRuntimeOverride() async throws {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        let seedModels = AISettingsSeedCatalog.getModelList()
        let bundles = AILocalScenarioBundleBuilder.buildCollection(
            allModels: seedModels,
            apiKeys: AISettingsSeedCatalog.getAPIKeyList(),
            scenarioBindings: AISettingsSeedCatalog.getScenarioBindings(for: seedModels)
        )

        let override = AIScenarioConfig(
            endpoint: "https://runtime.sparkclient.local/v1/chat/completions",
            model: "runtime-chat",
            apiKey: "runtime-key",
            temperature: 0.8,
            maxTokens: 1234
        )
        await runtimeStore.setOverride(override, for: .chat)

        let resolved = try await resolver.resolve(
            scenario: .chat,
            bundles: bundles,
            runtimeStore: runtimeStore,
            preferredModelName: nil
        )
        XCTAssertEqual(resolved.model, "runtime-chat")
        XCTAssertEqual(resolved.apiKey, "runtime-key")
        XCTAssertEqual(resolved.source, .runtimeOverride)
    }

    /// 防止 `APIKeys.json` 与 `JSONDecoder` 键策略不兼容时静默解码失败（整表 `nil` → 灌库 0 行）。
    func testAPIKeysSeedJSONDecodesToNonEmptyCatalog() {
        let keys = AISettingsSeedCatalog.getAPIKeyList()
        XCTAssertFalse(keys.isEmpty, "APIKeys.json 应解码为非空；若为 0 检查 APIKeySeedRow.CodingKeys 与 snake_case。")
    }

    func testLocalBundleDoesNotInferModelsWithoutScenarioBindings() {
        let model = AllModels(
            name: "local-chat",
            displayName: "Local Chat",
            identity: .model,
            position: 0,
            providerID: LocalModelService.localProviderID,
            company: LocalModelService.localCompany,
            isHidden: false,
            supportsSearch: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            source: .custom
        )

        let bundles = AILocalScenarioBundleBuilder.buildCollection(
            allModels: [model],
            apiKeys: [],
            scenarioBindings: []
        )

        XCTAssertTrue(bundles.bundle(for: .chat).models.isEmpty)
        XCTAssertTrue(bundles.bundle(for: .medicalCaseExtraction).models.isEmpty)
    }

    func testTrialPolicyFallsBackToDefaultFlagWhenNoSelection() {
        var snapshot = AISettingsSnapshot.default
        snapshot.trial = AITrialState(
            status: "active",
            isActive: true,
            grantSource: "auto",
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600),
            remainingSeconds: 3600
        )
        snapshot.trialModelPolicy = [
            AITrialModelPolicyItem(
                scenario: .chat,
                config: AIScenarioConfig(
                    endpoint: "https://a.example/v1/chat/completions",
                    model: "trial-a",
                    apiKey: nil,
                    temperature: 0.1,
                    maxTokens: 1024
                ),
                isDefault: false
            ),
            AITrialModelPolicyItem(
                scenario: .chat,
                config: AIScenarioConfig(
                    endpoint: "https://b.example/v1/chat/completions",
                    model: "trial-b",
                    apiKey: nil,
                    temperature: 0.2,
                    maxTokens: 2048
                ),
                isDefault: true
            ),
        ]
        XCTAssertEqual(snapshot.trialPolicyConfig(for: .chat)?.model, "trial-b")
    }

    func testScenarioDefaultModelOverridesChatPicker() {
        var snapshot = AISettingsSnapshot.default
        snapshot.setScenarioDefaultModelName("trial-a", for: .chat)
        snapshot.trial = AITrialState(
            status: "active",
            isActive: true,
            grantSource: "auto",
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600),
            remainingSeconds: 3600
        )
        snapshot.trialModelPolicy = [
            AITrialModelPolicyItem(
                scenario: .chat,
                config: AIScenarioConfig(
                    endpoint: "https://a.example/v1/chat/completions",
                    model: "trial-a",
                    apiKey: nil,
                    temperature: 0.1,
                    maxTokens: 1024
                ),
                isDefault: false
            ),
            AITrialModelPolicyItem(
                scenario: .chat,
                config: AIScenarioConfig(
                    endpoint: "https://b.example/v1/chat/completions",
                    model: "trial-b",
                    apiKey: nil,
                    temperature: 0.2,
                    maxTokens: 2048
                ),
                isDefault: true
            ),
        ]
        XCTAssertEqual(snapshot.trialPolicyConfig(for: .chat)?.model, "trial-b")
    }

    func testResolverPreservesProOverlaySourceForPreferredModel() async throws {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        let proBundle = AIScenarioRemoteBundle(
            defaultModelName: "pro-chat",
            models: [
                AIScenarioRemoteModelRow(
                    name: "pro-chat",
                    displayName: "Pro Chat",
                    identity: "model",
                    company: "SPARK",
                    endpoint: "https://pro.example/v1/chat/completions",
                    apiKey: nil,
                    supportsSearch: true,
                    supportsMultimodal: true,
                    supportsReasoning: true,
                    supportsToolUse: true,
                    supportsVoiceGen: false,
                    supportsImageGen: false,
                    supportsText: true,
                    supportsDeepReasoning: true,
                    reasoningControllable: false,
                    priceTier: 2,
                    systemProvision: nil,
                    icon: nil,
                    briefDescription: nil,
                    source: AIRecordSource.pro.rawValue,
                    aiScenarios: [AIScenario.chat.rawValue],
                    aiToolScenarios: [],
                    isDefault: true,
                    temperature: 0.2,
                    maxTokens: 4096
                )
            ]
        )
        var bundles = emptyScenarioBundles()
        bundles.setBundle(proBundle, for: .chat)

        let resolved = try await resolver.resolve(
            scenario: .chat,
            bundles: bundles,
            runtimeStore: runtimeStore,
            preferredModelName: "pro-chat"
        )

        XCTAssertEqual(resolved.model, "pro-chat")
        XCTAssertEqual(resolved.source, .proOverlay)
    }

    func testScenarioModelSourcesRoundTripThroughPreferencesPayload() throws {
        var snapshot = AISettingsSnapshot.default
        snapshot.setScenarioModelSource(.trial, for: .chat)

        let data = try JSONEncoder().encode(snapshot.preferencesPayload)
        let decoded = try JSONDecoder().decode(AISettingsSnapshot.PreferencesPayload.self, from: data)
        let restored = AISettingsSnapshot(allModels: [], apiKeys: [], preferences: decoded)

        XCTAssertEqual(restored.scenarioModelSource(for: .chat), .trial)
    }

    private func emptyScenarioBundles() -> AIScenarioRemoteBundlesCollection {
        let empty = AIScenarioRemoteBundle(defaultModelName: "", models: [])
        return AIScenarioRemoteBundlesCollection(
            chat: empty,
            embedding: empty,
            voice: empty,
            medicalStructuredExtraction: empty,
            medicalDocumentTypeRecognition: empty,
            medicalCaseExtraction: empty,
            healthExamExtraction: empty,
            medicalReportExtraction: empty,
            prescriptionExtraction: empty,
            medicationExtraction: empty,
            optimizationText: empty,
            optimizationVisual: empty,
            contextFolding: empty,
            router: empty,
            modelConfig: empty,
            reportInterpretation: empty
        )
    }
}
#endif
