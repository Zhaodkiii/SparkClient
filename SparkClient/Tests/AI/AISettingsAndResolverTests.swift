#if canImport(XCTest)
import XCTest

final class AISettingsAndResolverTests: XCTestCase {
    func testScenarioResolverPrefersRuntimeOverride() async throws {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        let bundles = AILocalScenarioBundleBuilder.buildCollection(
            allModels: AISettingsSeedCatalog.getModelList(),
            apiKeys: AISettingsSeedCatalog.getAPIKeyList(),
            scenarioDefaults: [:]
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
        snapshot.scenarioDefaultModels[AIScenario.chat.rawValue] = "trial-a"
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
}
#endif
