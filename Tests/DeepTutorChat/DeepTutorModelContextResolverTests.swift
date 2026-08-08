import XCTest
@testable import SparkClient

final class DeepTutorModelContextResolverTests: XCTestCase {
    func testResolveAgentUsesAgentPromptSource() throws {
        let bundles = Self.makeBundles(
            models: [
                Self.makeRow(
                    name: "health-agent",
                    identity: .agent,
                    systemProvision: "You are a health planning agent.",
                    baseModelName: "gpt-test",
                    aiToolScenarios: [SparkToolName.queryMemberProfile.rawValue]
                ),
            ],
            defaultName: "health-agent"
        )
        let context = try DeepTutorModelContextResolver.resolve(
            bundles: bundles,
            conversation: DeepTutorConversation(title: "Test"),
            snapshot: nil,
            composerSelectedModelName: "health-agent",
            mode: .liveSend
        )

        XCTAssertEqual(context.identity, .agent)
        XCTAssertEqual(context.promptSource, .agent)
        XCTAssertEqual(context.baseModelName, "gpt-test")
        XCTAssertEqual(context.modelAllowedToolNames, Set([SparkToolName.queryMemberProfile.rawValue]))
    }

    func testModelToolMergerDisablesAllToolsWhenAgentWhitelistIsEmpty() {
        let deepPolicy = DeepTutorToolPolicyResult(
            useTools: true,
            useKnowledgeBag: true,
            useWebSearch: true,
            allowedToolNames: Set([
                SparkToolName.askUserQuestion.rawValue,
                SparkToolName.queryWeather.rawValue,
            ]),
            policyReason: "test",
            mountFlags: [:],
            suppressedToolNames: [],
            requestedCanonicalTools: [],
            resolvedCanonicalTools: [],
            autoMountedCanonicalTools: [],
            aliasFailures: [],
            intentHints: [],
            structuredIntents: [],
            domainExtensionResults: [],
            healthDataEligible: false,
            healthDataIneligibleReason: nil,
            perTurnSnapshot: Self.makeEmptyToolSnapshot()
        )

        let merged = DeepTutorModelToolMerger.merge(
            deepTutorPolicy: deepPolicy,
            modelRestriction: DeepTutorModelToolRestrictionResolver.restriction(
                from: [SparkToolName.noSelectionSentinel]
            )
        )

        XCTAssertFalse(merged.policy.useTools)
        XCTAssertTrue(merged.finalAllowedToolNames.isEmpty)
    }

    func testModelToolMergerIntersectsDeepTutorPolicyWithAgentWhitelist() {
        let deepPolicy = DeepTutorToolPolicyResult(
            useTools: true,
            useKnowledgeBag: false,
            useWebSearch: false,
            allowedToolNames: Set([
                SparkToolName.askUserQuestion.rawValue,
                SparkToolName.queryWeather.rawValue,
            ]),
            policyReason: "test",
            mountFlags: [:],
            suppressedToolNames: [],
            requestedCanonicalTools: [],
            resolvedCanonicalTools: [],
            autoMountedCanonicalTools: [],
            aliasFailures: [],
            intentHints: [],
            structuredIntents: [],
            domainExtensionResults: [],
            healthDataEligible: false,
            healthDataIneligibleReason: nil,
            perTurnSnapshot: Self.makeEmptyToolSnapshot()
        )

        let merged = DeepTutorModelToolMerger.merge(
            deepTutorPolicy: deepPolicy,
            modelRestriction: DeepTutorModelToolRestrictionResolver.restriction(
                from: [
                    SparkToolName.askUserQuestion.rawValue,
                    SparkToolName.queryMemberProfile.rawValue,
                ]
            )
        )

        XCTAssertEqual(merged.finalAllowedToolNames, Set([SparkToolName.askUserQuestion.rawValue]))
    }

    func testReplaySnapshotPrefersStoredModelOverCurrentSelection() throws {
        let bundles = Self.makeBundles(
            models: [
                Self.makeRow(name: "model-a", identity: .model),
                Self.makeRow(
                    name: "agent-b",
                    identity: .agent,
                    systemProvision: "Agent B",
                    baseModelName: "model-a"
                ),
            ],
            defaultName: "model-a"
        )
        let snapshot = DeepTutorRequestSnapshot(selectedModelName: "agent-b")
        let context = try DeepTutorModelContextResolver.resolve(
            bundles: bundles,
            conversation: DeepTutorConversation(title: "Test", currentModelName: "model-a"),
            snapshot: snapshot,
            composerSelectedModelName: "model-a",
            mode: .replaySnapshot
        )

        XCTAssertEqual(context.selectedModelName, "agent-b")
        XCTAssertEqual(context.identity, .agent)
    }

    func testAgentGenerationParametersIgnoreConversationTemperature() {
        let context = DeepTutorResolvedModelContext(
            selectedModelName: "agent",
            identity: .agent,
            displayTitle: "Agent",
            baseModelName: "base",
            systemPrompt: "prompt",
            aiToolScenarios: [],
            supportsToolUse: true,
            supportsMultimodal: true,
            temperature: 0.1,
            maxTokens: 4096,
            promptSource: .agent,
            modelAllowedToolNames: nil
        )
        let params = DeepTutorModelContextResolver.generationParameters(
            context: context,
            conversation: DeepTutorConversation(title: "Test", temperature: 0.9, maxMessages: 12),
            resolvedConfigMaxTokens: 1024
        )

        XCTAssertEqual(params.temperature, 0.1)
        XCTAssertEqual(params.maxTokens, 4096)
        XCTAssertEqual(params.maxMessages, 12)
    }

    private static func makeBundles(
        models: [AIScenarioRemoteModelRow],
        defaultName: String
    ) -> AIScenarioRemoteBundlesCollection {
        let chat = AIScenarioRemoteBundle(defaultModelName: defaultName, models: models)
        let empty = AIScenarioRemoteBundle(defaultModelName: "", models: [])
        return AIScenarioRemoteBundlesCollection(
            chat: chat,
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

    private static func makeEmptyToolSnapshot() -> DeepTutorPerTurnToolSnapshot {
        DeepTutorPerTurnToolSnapshot(
            capability: .chat,
            requestedCanonicalTools: [],
            resolvedCanonicalTools: [],
            resolvedSparkToolNames: [],
            autoMountedCanonicalTools: [],
            suppressedCanonicalTools: [],
            aliasFailures: [],
            intentHints: [],
            policyReason: "test",
            mountFlags: [:],
            modelSupportsNativeTools: true
        )
    }

    private static func makeRow(
        name: String,
        identity: AIModelIdentity,
        systemProvision: String? = nil,
        baseModelName: String? = nil,
        aiToolScenarios: [String] = []
    ) -> AIScenarioRemoteModelRow {
        AIScenarioRemoteModelRow(
            name: name,
            displayName: name,
            identity: identity.rawValue,
            providerID: "OPENAI",
            company: "OPENAI",
            endpoint: "https://example.com",
            apiKey: "key",
            supportsSearch: false,
            supportsMultimodal: true,
            supportsReasoning: false,
            supportsToolUse: true,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 0,
            systemProvision: systemProvision,
            icon: nil,
            briefDescription: nil,
            source: AIRecordSource.custom.rawValue,
            aiScenarios: [AIScenario.chat.rawValue],
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: [],
            isDefault: false,
            temperature: 0.2,
            maxTokens: 2048,
            baseModelName: baseModelName
        )
    }
}
