#if canImport(XCTest)
import XCTest

final class ScenarioPolicyResolverTests: XCTestCase {
    func testResolverFallsBackToLocalCatalogDefaultRow() async throws {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        var bundles = emptyScenarioBundles()
        let row = makeModelRow(
            name: "local-chat",
            source: AIRecordSource.custom.rawValue,
            isDefault: true
        )
        bundles.setBundle(
            AIScenarioRemoteBundle(defaultModelName: "local-chat", models: [row]),
            for: .chat
        )

        let resolved = try await resolver.resolve(
            scenario: .chat,
            bundles: bundles,
            runtimeStore: runtimeStore,
            preferredModelName: nil
        )

        XCTAssertEqual(resolved.model, "local-chat")
        XCTAssertEqual(resolved.source, .localCatalog)
    }

    /// `ScenarioPolicyResolver` 的 bundle 路径不会产出 `.trialPolicy`；
    /// 该来源由 Guest 等 runtime bypass 路径通过 `toResolvedConfig(source:)` 显式标记。
    func testResolverUsesTrialPolicySourceWhenTrialConfigIsDefault() throws {
        let config = AIScenarioConfig(
            endpoint: "https://trial.example/v1/chat/completions",
            model: "trial-chat",
            apiKey: "trial-key",
            temperature: 0.3,
            maxTokens: 512
        )
        let resolved = try config.toResolvedConfig(source: .trialPolicy)
        XCTAssertEqual(resolved.model, "trial-chat")
        XCTAssertEqual(resolved.source, .trialPolicy)
    }

    func testResolverThrowsMissingModelWhenPreferredModelNotInBundle() async {
        let runtimeStore = AIRuntimeStore()
        let resolver = ScenarioPolicyResolver()
        var bundles = emptyScenarioBundles()
        bundles.setBundle(
            AIScenarioRemoteBundle(
                defaultModelName: "local-chat",
                models: [makeModelRow(name: "local-chat", source: AIRecordSource.custom.rawValue, isDefault: true)]
            ),
            for: .chat
        )

        do {
            _ = try await resolver.resolve(
                scenario: .chat,
                bundles: bundles,
                runtimeStore: runtimeStore,
                preferredModelName: "missing-model"
            )
            XCTFail("Expected AIConfigError.missingModelForScenario")
        } catch let error as AIConfigError {
            guard case .missingModelForScenario(let scenario) = error else {
                XCTFail("Unexpected AIConfigError: \(error)")
                return
            }
            XCTAssertEqual(scenario, .chat)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeModelRow(
        name: String,
        source: String,
        isDefault: Bool
    ) -> AIScenarioRemoteModelRow {
        AIScenarioRemoteModelRow(
            name: name,
            displayName: name,
            identity: AIModelIdentity.model.rawValue,
            company: "SPARK",
            endpoint: "https://local.example/v1/chat/completions",
            apiKey: nil,
            supportsSearch: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 1,
            systemProvision: nil,
            icon: nil,
            briefDescription: nil,
            source: source,
            aiScenarios: [AIScenario.chat.rawValue],
            aiToolScenarios: [],
            isDefault: isDefault,
            temperature: 0.2,
            maxTokens: 2048
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
