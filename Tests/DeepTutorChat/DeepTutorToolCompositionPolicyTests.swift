import XCTest
@testable import SparkClient

final class DeepTutorToolCompositionPolicyTests: XCTestCase {
    func testChatGreetingDoesNotOpenToolsFromKeywords() {
        let context = makeContext(userInput: "你好 哈哈哈", capability: .chat, requestedTools: [])
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.intentHints.contains("casual_chat"))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.askUserQuestion.rawValue))
    }

    func testChatDoesNotOpenWebSearchFromKeywordsWhenUserDisabled() {
        let context = makeContext(
            userInput: "查一下最新研究",
            capability: .chat,
            requestedTools: []
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.intentHints.contains("web_search"))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
    }

    func testChatOpensWebSearchWhenUserEnabled() {
        let context = makeContext(
            userInput: "查一下最新研究",
            capability: .chat,
            requestedTools: [DeepTutorCanonicalToolName.webSearch.rawValue]
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
        XCTAssertTrue(policy.requestedCanonicalTools.contains(DeepTutorCanonicalToolName.webSearch.rawValue))
    }

    func testDeepQuestionUsesManifestDefaultsNotHealthKeywords() {
        let context = makeContext(
            userInput: "健康知识给我来一些",
            capability: .deepQuestion,
            requestedTools: nil
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertEqual(
            policy.requestedCanonicalTools,
            [
                DeepTutorCanonicalToolName.webSearch.rawValue,
                DeepTutorCanonicalToolName.codeExecution.rawValue,
            ]
        )
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
        XCTAssertTrue(policy.aliasFailures.contains { $0.hasPrefix("code_execution:") })
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchStepDetails.rawValue))
    }

    func testSnapshotReplayPreservesRequestedToolsOnRegenerate() {
        let snapshot = DeepTutorRequestSnapshot(
            capability: .chat,
            enabledTools: [DeepTutorCanonicalToolName.webSearch.rawValue],
            toolSnapshot: DeepTutorPerTurnToolSnapshot(
                capability: .chat,
                requestedCanonicalTools: [DeepTutorCanonicalToolName.webSearch.rawValue],
                resolvedCanonicalTools: [DeepTutorCanonicalToolName.webSearch.rawValue],
                resolvedSparkToolNames: [SparkToolName.searchOnline.rawValue],
                autoMountedCanonicalTools: [],
                suppressedCanonicalTools: [],
                aliasFailures: [],
                intentHints: [],
                policyReason: "compose",
                mountFlags: [:],
                modelSupportsNativeTools: true,
                toolPhase: DeepTutorToolPipelinePhase.answerLoop.rawValue
            )
        )

        var context = makeContext(userInput: "retry", capability: .chat, requestedTools: [])
        context.snapshotRequestedTools = snapshot.enabledTools
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.requestedCanonicalTools.contains(DeepTutorCanonicalToolName.webSearch.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
    }

    func testAliasMapMapsCanonicalAskUserAndWebSearch() {
        let askUser = DeepTutorToolAliasMap.resolve(canonicalName: "ask_user")
        XCTAssertEqual(askUser.status, .mapped)
        XCTAssertEqual(askUser.sparkToolNames, [SparkToolName.askUserQuestion.rawValue])

        let webSearch = DeepTutorToolAliasMap.resolve(canonicalName: "web_search")
        XCTAssertEqual(webSearch.status, .mapped)
        XCTAssertEqual(webSearch.sparkToolNames, [SparkToolName.searchOnline.rawValue])
    }

    private func makeContext(
        userInput: String,
        capability: DeepTutorCapability,
        requestedTools: [String]?
    ) -> DeepTutorToolMountContext {
        var context = DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: UUID(),
            conversationTitle: "Test"
        )
        context.snapshotRequestedTools = requestedTools
        if capability == .deepQuestion, requestedTools == nil {
            context.snapshotRequestedTools = DeepTutorCapabilityToolManifest.manifest(for: .deepQuestion).defaultTools
        }
        return context
    }
}
