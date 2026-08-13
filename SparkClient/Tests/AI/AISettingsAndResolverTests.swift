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

    func testChatComposerStartupPreferencesRoundTripThroughPreferencesPayload() throws {
        var snapshot = AISettingsSnapshot.default
        snapshot.chatComposerStartupPreferences = ChatComposerStartupPreferences(
            memberProfileEnabled: true,
            useTools: true,
            useKnowledgeBag: false,
            useWebSearch: false,
            reasoningEnabled: true,
            reasoningEffortTier: 3
        )

        let data = try JSONEncoder().encode(snapshot.preferencesPayload)
        let decoded = try JSONDecoder().decode(AISettingsSnapshot.PreferencesPayload.self, from: data)
        let restored = AISettingsSnapshot(allModels: [], apiKeys: [], preferences: decoded)

        XCTAssertEqual(restored.chatComposerStartupPreferences, snapshot.chatComposerStartupPreferences)
    }

    func testChatComposerRuntimeFlagsStartFromStartupPreferences() {
        let prefs = ChatComposerStartupPreferences(
            memberProfileEnabled: false,
            useTools: true,
            useKnowledgeBag: false,
            useWebSearch: false,
            reasoningEnabled: true,
            reasoningEffortTier: 2
        )

        let flags = ChatComposerRuntimeFlags(startupPreferences: prefs)

        XCTAssertTrue(flags.useTools)
        XCTAssertFalse(flags.useKnowledgeBag)
        XCTAssertFalse(flags.useWebSearch)
        XCTAssertTrue(flags.reasoningEnabled)
        XCTAssertEqual(flags.reasoningEffortTier, 2)
        XCTAssertNil(flags.selectedChatModelName)
    }

    func testChatConversationUIDefaultsToSwiftUINewArchitecture() {
        XCTAssertEqual(ChatConversationUIPreferences.fallback.architecture, .swiftUI)
        XCTAssertEqual(ChatConversationUIPreferences.fallback.swiftUIRefreshBehavior, .stable)
    }

    func testChatConversationAppearanceDefaultsToolResultCardsIntoBody() {
        XCTAssertEqual(ChatConversationAppearancePreferences.fallback.cardStyle, .bodyFocused)
        XCTAssertTrue(ChatConversationAppearancePreferences.fallback.separatesToolPresentationsInBodyFocused)
    }

    func testToolConsentPreferencesRoundTripThroughPreferencesPayload() throws {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolModelEgressConsentPreferences.defaultMode = .alwaysDeny
        snapshot.toolModelEgressConsentPreferences.setMode(.alwaysAllow, for: SparkToolName.getCurrentLocation.rawValue)

        let data = try JSONEncoder().encode(snapshot.preferencesPayload)
        let decoded = try JSONDecoder().decode(AISettingsSnapshot.PreferencesPayload.self, from: data)
        let restored = AISettingsSnapshot(allModels: [], apiKeys: [], preferences: decoded)

        XCTAssertEqual(restored.toolModelEgressConsentPreferences.defaultMode, .alwaysDeny)
        XCTAssertEqual(
            restored.toolModelEgressConsentPreferences.mode(for: SparkToolName.getCurrentLocation.rawValue),
            .alwaysAllow
        )
    }

    func testToolConsentPreferencesInheritDefaultMode() {
        let preferences = ToolModelEgressConsentPreferences(
            defaultMode: .alwaysDeny,
            toolPreferences: []
        )

        XCTAssertEqual(preferences.mode(for: SparkToolName.queryWeather.rawValue), .alwaysDeny)
    }

    func testToolConsentPreferencesDefaultSeedsLocationAndWeatherAsAlwaysAllow() {
        let preferences = ToolModelEgressConsentPreferences.default

        XCTAssertEqual(preferences.mode(for: SparkToolName.getCurrentLocation.rawValue), .alwaysAllow)
        XCTAssertEqual(preferences.mode(for: SparkToolName.queryLocation.rawValue), .alwaysAllow)
        XCTAssertEqual(preferences.mode(for: SparkToolName.queryWeather.rawValue), .alwaysAllow)
    }

    func testToolConsentPreferencesCanClearExplicitOverride() {
        var preferences = ToolModelEgressConsentPreferences(defaultMode: .askEveryTime)
        preferences.setMode(.alwaysAllow, for: SparkToolName.queryWeather.rawValue)

        preferences.clearPreference(for: SparkToolName.queryWeather.rawValue)

        XCTAssertNil(preferences.preference(for: SparkToolName.queryWeather.rawValue))
        XCTAssertEqual(preferences.mode(for: SparkToolName.queryWeather.rawValue), .askEveryTime)
    }

    func testToolConsentPolicyAsksEveryTimeForManagedSensitiveToolWithRemoteProvider() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolModelEgressConsentPreferences = ToolModelEgressConsentPreferences(defaultMode: .askEveryTime)
        let result = ToolExecutionResult(
            toolName: SparkToolName.getCurrentLocation.rawValue,
            outputText: "lat=1,lng=2",
            sensitive: true,
            shouldBypassModel: false
        )

        let resolution = ToolModelEgressConsentPolicy().evaluate(
            result: result,
            providerCompany: "OpenAI",
            snapshot: snapshot
        )

        XCTAssertEqual(resolution, .askEveryTime)
    }

    func testToolConsentPolicySkipsPromptWhenHealthToolHasNoUserData() {
        let snapshot = AISettingsSnapshot.default
        let noWorkoutText = """
        \(L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found."))
        查询区间：2026-08-13 至 2026-08-13。
        可能原因：HealthKit 在该区间没有样本、未授权读取步数/能量/运动数据，或当前设备/模拟器没有 Apple 健康数据。
        """
        let result = ToolExecutionResult(
            toolName: SparkToolName.fetchWorkoutDetails.rawValue,
            outputText: noWorkoutText,
            sensitive: true,
            shouldBypassModel: true
        )

        let resolution = ToolModelEgressConsentPolicy().evaluate(
            result: result,
            providerCompany: "Doubao",
            snapshot: snapshot
        )

        XCTAssertEqual(resolution, .allowWithoutPrompt)
    }

    func testToolConsentPolicyHonorsAlwaysAllowAndAlwaysDenyModes() {
        var allowSnapshot = AISettingsSnapshot.default
        allowSnapshot.toolModelEgressConsentPreferences.setMode(.alwaysAllow, for: SparkToolName.fetchSleepDetails.rawValue)

        let result = ToolExecutionResult(
            toolName: SparkToolName.fetchSleepDetails.rawValue,
            outputText: "sleep",
            sensitive: true,
            shouldBypassModel: false
        )

        XCTAssertEqual(
            ToolModelEgressConsentPolicy().evaluate(
                result: result,
                providerCompany: "Doubao",
                snapshot: allowSnapshot
            ),
            .allowWithoutPrompt
        )

        var denySnapshot = AISettingsSnapshot.default
        denySnapshot.toolModelEgressConsentPreferences.setMode(.alwaysDeny, for: SparkToolName.fetchSleepDetails.rawValue)

        let denyResolution = ToolModelEgressConsentPolicy().evaluate(
            result: result,
            providerCompany: "Doubao",
            snapshot: denySnapshot
        )

        guard case .deny(let reason) = denyResolution else {
            XCTFail("Expected deny resolution")
            return
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testToolConsentPolicyBypassesPromptForLocalProvider() {
        let snapshot = AISettingsSnapshot.default
        let result = ToolExecutionResult(
            toolName: SparkToolName.getCurrentLocation.rawValue,
            outputText: "lat=1,lng=2",
            sensitive: true,
            shouldBypassModel: false
        )

        let resolution = ToolModelEgressConsentPolicy().evaluate(
            result: result,
            providerCompany: "LOCAL",
            snapshot: snapshot
        )

        XCTAssertEqual(resolution, .allowWithoutPrompt)
    }

    func testToolConsentDescriptorUsesCategoryEnumInsteadOfLocalizedTitle() {
        let locationDescriptor = ToolModelEgressConsentPolicy.descriptor(for: SparkToolName.getCurrentLocation.rawValue)
        let weatherDescriptor = ToolModelEgressConsentPolicy.descriptor(for: SparkToolName.queryWeather.rawValue)
        let healthDescriptor = ToolModelEgressConsentPolicy.descriptor(for: SparkToolName.fetchSleepDetails.rawValue)

        XCTAssertEqual(locationDescriptor?.category, .location)
        XCTAssertEqual(weatherDescriptor?.category, .weather)
        XCTAssertEqual(healthDescriptor?.category, .health)
        XCTAssertEqual(locationDescriptor?.categoryTitle, locationDescriptor?.category.displayTitle)
    }

    func testToolConsentDescriptorLocalizedSummaryUsesKeyPrefix() {
        guard let descriptor = ToolModelEgressConsentPolicy.descriptor(for: SparkToolName.getCurrentLocation.rawValue) else {
            XCTFail("Expected descriptor")
            return
        }

        XCTAssertEqual(
            descriptor.summary,
            L10n.text(
                "ai_settings.tool_consent.descriptor.get_current_location.summary",
                fallback: "将当前位置作为模型上下文输入，用于天气、地点和位置相关回答。"
            )
        )
        XCTAssertEqual(descriptor.dataLines.count, 3)
        XCTAssertFalse(descriptor.dataLines[0].isEmpty)
    }

    func testToolConsentPolicyAlwaysDenyReasonUsesLocalizationKey() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolModelEgressConsentPreferences.setMode(.alwaysDeny, for: SparkToolName.fetchSleepDetails.rawValue)

        let result = ToolExecutionResult(
            toolName: SparkToolName.fetchSleepDetails.rawValue,
            outputText: "sleep",
            sensitive: true,
            shouldBypassModel: false
        )

        let resolution = ToolModelEgressConsentPolicy().evaluate(
            result: result,
            providerCompany: "Doubao",
            snapshot: snapshot
        )

        guard case .deny(let reason) = resolution else {
            XCTFail("Expected deny resolution")
            return
        }

        XCTAssertEqual(
            reason,
            L10n.text(
                "ai_settings.tool_consent.runtime.always_deny_reason",
                fallback: "用户已将该工具配置为永久拒绝发送到 AI。"
            )
        )
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
            medicineBoxExtraction: empty,
            optimizationText: empty,
            optimizationVisual: empty,
            contextFolding: empty,
            router: empty,
            modelConfig: empty,
            reportInterpretation: empty,
            nutritionIntakeExtraction: empty
        )
    }
}
#endif
