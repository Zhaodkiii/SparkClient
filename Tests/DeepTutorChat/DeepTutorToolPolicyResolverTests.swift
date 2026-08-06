import XCTest
@testable import SparkClient

final class DeepTutorToolPolicyResolverTests: XCTestCase {
    func testWebSearchEnabledMapsToSearchOnlineWithUseWebSearchTrue() {
        let context = makeContext(
            userInput: "请搜索今天最新的 Apple Developer 新闻",
            capability: .chat,
            requestedTools: [DeepTutorCanonicalToolName.webSearch.rawValue]
        )

        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.useWebSearch)
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
        XCTAssertTrue(policy.requestedCanonicalTools.contains(DeepTutorCanonicalToolName.webSearch.rawValue))
    }

    func testWebSearchDisabledDoesNotExposeSearchOnline() {
        let context = makeContext(
            userInput: "请搜索今天最新的 Apple Developer 新闻",
            capability: .chat,
            requestedTools: []
        )

        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertFalse(policy.useWebSearch)
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
    }

    func testDeepQuestionDefaultToolsEnableWebSearchPolicy() {
        var context = makeContext(
            userInput: "解释量子纠缠",
            capability: .deepQuestion,
            requestedTools: nil
        )
        context.snapshotRequestedTools = DeepTutorCapabilityToolManifest.manifest(for: .deepQuestion).defaultTools

        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.useWebSearch)
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
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
        return context
    }
}
