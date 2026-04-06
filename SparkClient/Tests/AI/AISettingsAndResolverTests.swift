#if canImport(XCTest)
import XCTest

final class AISettingsAndResolverTests: XCTestCase {
    private enum Constants {
        static let snapshotStorageKey = "spark.ai.settings.snapshot.v1"
        static let seedVersionStorageKey = "spark.ai.settings.seed.version.v1"
    }

    func testRepositorySavesSecretsToSecretStore() async throws {
        let suiteName = "ai.settings.tests.\(UUID().uuidString)"
        let userDefaults = try makeUserDefaults(suiteName: suiteName)
        let secretStore = InMemoryAISettingsSecretStore()
        let repository = DefaultAISettingsRepository(
            userDefaults: userDefaults,
            secretStore: secretStore,
            logger: ConsoleLogger()
        )

        var snapshot = AISettingsSnapshot.default
        snapshot.chat.apiKey = "chat-secret"
        snapshot.optimizationText.apiKey = "extract-secret"
        snapshot.apiKeys[0].key = "api-secret"
        snapshot.searchKeys[0].key = "search-secret"
        snapshot.toolKeys[0].key = "tool-secret"

        try await repository.save(snapshot: snapshot)

        let persistedData = try XCTUnwrap(userDefaults.data(forKey: Constants.snapshotStorageKey))
        let persistedSnapshot = try JSONDecoder().decode(AISettingsSnapshot.self, from: persistedData)
        XCTAssertNil(persistedSnapshot.chat.apiKey)
        XCTAssertNil(persistedSnapshot.optimizationText.apiKey)
        XCTAssertEqual(persistedSnapshot.apiKeys[0].key, "")
        XCTAssertEqual(persistedSnapshot.searchKeys[0].key, "")
        XCTAssertEqual(persistedSnapshot.toolKeys[0].key, "")

        let loaded = await repository.loadSnapshot()
        XCTAssertEqual(loaded.chat.apiKey, "chat-secret")
        XCTAssertEqual(loaded.optimizationText.apiKey, "extract-secret")
        XCTAssertEqual(loaded.apiKeys[0].key, "api-secret")
        XCTAssertEqual(loaded.searchKeys[0].key, "search-secret")
        XCTAssertEqual(loaded.toolKeys[0].key, "tool-secret")
    }

    func testRepositoryMigratesLegacyPlaintextSecrets() async throws {
        let suiteName = "ai.settings.tests.migrate.\(UUID().uuidString)"
        let userDefaults = try makeUserDefaults(suiteName: suiteName)
        let secretStore = InMemoryAISettingsSecretStore()
        let repository = DefaultAISettingsRepository(
            userDefaults: userDefaults,
            secretStore: secretStore,
            logger: ConsoleLogger()
        )

        var legacySnapshot = AISettingsSnapshot.default
        legacySnapshot.chat.apiKey = "legacy-chat"
        legacySnapshot.apiKeys[0].key = "legacy-api"
        let legacyData = try JSONEncoder().encode(legacySnapshot)
        userDefaults.set(legacyData, forKey: Constants.snapshotStorageKey)
        userDefaults.set(AISettingsSeedCatalog.version, forKey: Constants.seedVersionStorageKey)

        let loaded = await repository.loadSnapshot()
        XCTAssertEqual(loaded.chat.apiKey, "legacy-chat")
        XCTAssertEqual(loaded.apiKeys[0].key, "legacy-api")

        let persistedData = try XCTUnwrap(userDefaults.data(forKey: Constants.snapshotStorageKey))
        let persistedSnapshot = try JSONDecoder().decode(AISettingsSnapshot.self, from: persistedData)
        XCTAssertNil(persistedSnapshot.chat.apiKey)
        XCTAssertEqual(persistedSnapshot.apiKeys[0].key, "")
    }

    func testScenarioResolverPrefersRuntimeOverride() async throws {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        let snapshot = AISettingsSnapshot.default

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
            snapshot: snapshot,
            runtimeStore: runtimeStore
        )
        XCTAssertEqual(resolved.model, "runtime-chat")
        XCTAssertEqual(resolved.apiKey, "runtime-key")
        XCTAssertEqual(resolved.source, .runtimeOverride)
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

    func testTrialPolicyUsesScenarioSelectedModelWhenMultipleRows() {
        var snapshot = AISettingsSnapshot.default
        snapshot.trial = AITrialState(
            status: "active",
            isActive: true,
            grantSource: "auto",
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600),
            remainingSeconds: 3600
        )
        snapshot.scenarioSelectedModel[AIScenario.chat.rawValue] = "trial-a"
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
        XCTAssertEqual(snapshot.trialPolicyConfig(for: .chat)?.model, "trial-a")
    }

    func testScenarioResolverUsesTrialPolicyWhenNoRuntimeOverride() async throws {
        let runtimeStore = AIRuntimeStore()
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
                    endpoint: "https://trial.sparkclient.local/v1/chat/completions",
                    model: "trial-chat",
                    apiKey: nil,
                    temperature: 0.1,
                    maxTokens: 1024
                ),
                isDefault: true
            )
        ]

        let resolver = ScenarioPolicyResolver()
        let resolved = try await resolver.resolve(
            scenario: .chat,
            snapshot: snapshot,
            runtimeStore: runtimeStore
        )
        XCTAssertEqual(resolved.model, "trial-chat")
        XCTAssertEqual(resolved.source, .trialPolicy)
    }

    func testSnapshotMergesRemotePatchAndKeepsCustomAPIKey() {
        var snapshot = AISettingsSnapshot.default
        snapshot.chat.model = "local-chat"
        snapshot.userInfo.useSearch = true

        var customAPI = snapshot.apiKeys[0]
        customAPI.source = .custom
        customAPI.key = "custom-key"
        customAPI.requestURL = "https://custom.example.com/v1/chat/completions"
        snapshot.apiKeys = [customAPI]

        let remoteAPI = APIKeys(
            name: customAPI.name,
            company: customAPI.company,
            key: "",
            requestURL: "https://remote.sparkservice.local/v1/chat/completions",
            isHidden: false,
            help: "remote",
            source: .system,
            timestamp: Date()
        )

        let remotePatch = AIRemoteSettingsPatch(
            revision: "2026-04-03",
            chat: AIScenarioConfig(
                endpoint: "https://remote.sparkservice.local/v1/chat/completions",
                model: "remote-chat-model",
                apiKey: nil,
                temperature: 0.1,
                maxTokens: 8192
            ),
            apiKeys: [remoteAPI],
            userInfo: AIRemoteUserInfoPatch(
                useSearch: false,
                searchCount: 12
            ),
            trial: AITrialState(
                status: "active",
                isActive: true,
                grantSource: "application",
                startedAt: nil,
                expiresAt: nil,
                remainingSeconds: 100
            ),
            trialModelPolicy: [
                AITrialModelPolicyItem(
                    scenario: .chat,
                    config: AIScenarioConfig(
                        endpoint: "https://trial.sparkservice.local/v1/chat/completions",
                        model: "trial-chat-model",
                        apiKey: nil,
                        temperature: 0.0,
                        maxTokens: 2000
                    ),
                    isDefault: true
                )
            ]
        )

        let merged = snapshot.merging(remotePatch: remotePatch)
        XCTAssertEqual(merged.chat.model, "remote-chat-model")
        XCTAssertEqual(merged.trial.status, "active")
        XCTAssertEqual(merged.trialModelPolicy.first?.config.model, "trial-chat-model")
        XCTAssertEqual(merged.chat.maxTokens, 8192)
        XCTAssertEqual(merged.userInfo.useSearch, false)
        XCTAssertEqual(merged.userInfo.searchCount, 12)

        guard let mergedAPI = merged.apiKeys.first else {
            XCTFail("expected merged api key")
            return
        }
        XCTAssertEqual(mergedAPI.source, .custom)
        XCTAssertEqual(mergedAPI.key, "custom-key")
        XCTAssertEqual(mergedAPI.requestURL, "https://remote.sparkservice.local/v1/chat/completions")
    }

    private func makeUserDefaults(suiteName: String) throws -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "AISettingsTests", code: -1)
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
#endif
