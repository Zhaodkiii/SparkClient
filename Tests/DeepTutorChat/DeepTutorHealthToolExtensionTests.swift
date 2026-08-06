import XCTest
@testable import SparkClient

final class DeepTutorHealthToolExtensionTests: XCTestCase {
    func testSleepQueryWithoutMemberOpensMemberSelection() {
        let context = makeContext(
            userInput: "我最近的睡眠怎么样 今天是20260806",
            capability: .chat,
            hasSelectedMember: false
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.intentHints.contains("health_data"))
        XCTAssertEqual(
            policy.structuredIntents.first { $0.domain == .healthData }?.subdomain,
            .sleep
        )
        XCTAssertEqual(
            policy.structuredIntents.first { $0.domain == .healthData }?.dateAnchor,
            "2026-08-06"
        )
        XCTAssertEqual(
            policy.structuredIntents.first { $0.domain == .healthData }?.timeRange,
            .recent
        )
        XCTAssertTrue(policy.healthDataEligible)
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.requestMemberSelection.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.getCurrentMember.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchSleepDetails.rawValue))

        let mode = DeepTutorPromptBuilder.healthPromptMode(allowedToolNames: policy.allowedToolNames)
        XCTAssertEqual(mode, .memberSelectionRequired)
        let prompt = DeepTutorPromptBuilder.build(
            capability: .chat,
            conversationTitle: "Test",
            rolePrompt: nil,
            healthPromptMode: mode
        ).systemPrompt
        XCTAssertTrue(prompt.contains("request_member_selection"))
        let mismatches = DeepTutorPromptSchemaConsistencyChecker.mismatchedTools(
            prompt: prompt,
            schemaNames: Array(policy.allowedToolNames)
        )
        XCTAssertTrue(mismatches.isEmpty)
    }

    func testSleepQueryWithMemberOpensFetchSleepDetails() {
        let context = makeContext(
            userInput: "我最近的睡眠怎么样 今天是20260806",
            capability: .chat,
            hasSelectedMember: true
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.healthDataEligible)
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.fetchSleepDetails.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.requestMemberSelection.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchStepDetails.rawValue))

        let mode = DeepTutorPromptBuilder.healthPromptMode(allowedToolNames: policy.allowedToolNames)
        XCTAssertEqual(mode, .healthFetchAvailable)
        let prompt = DeepTutorPromptBuilder.build(
            capability: .chat,
            conversationTitle: "Test",
            rolePrompt: nil,
            healthPromptMode: mode
        ).systemPrompt
        XCTAssertTrue(prompt.contains("fetch_sleep_details"))
        XCTAssertFalse(prompt.contains("Call `request_member_selection` first"))
        let mismatches = DeepTutorPromptSchemaConsistencyChecker.mismatchedTools(
            prompt: prompt,
            schemaNames: Array(policy.allowedToolNames)
        )
        XCTAssertTrue(mismatches.isEmpty)
    }

    func testHealthCapabilityUnavailableDoesNotMountHealthTools() {
        var context = makeContext(
            userInput: "我最近的睡眠怎么样",
            capability: .chat,
            hasSelectedMember: false
        )
        context.healthDataCapabilityAvailable = false
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertFalse(policy.healthDataEligible)
        XCTAssertEqual(policy.healthDataIneligibleReason, "health_capability_unavailable")
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.requestMemberSelection.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchSleepDetails.rawValue))

        let mode = DeepTutorPromptBuilder.healthPromptMode(allowedToolNames: policy.allowedToolNames)
        XCTAssertEqual(mode, .unavailable)
        let prompt = DeepTutorPromptBuilder.build(
            capability: .chat,
            conversationTitle: "Test",
            rolePrompt: nil,
            healthPromptMode: mode
        ).systemPrompt
        XCTAssertFalse(prompt.contains("request_member_selection"))
        XCTAssertTrue(prompt.contains("do not currently have access"))
    }

    func testMemberSelectionResumeOpensSleepFetch() {
        var context = makeContext(
            userInput: "我最近的睡眠怎么样 今天是20260806",
            capability: .chat,
            hasSelectedMember: false
        )
        let prior = DeepTutorToolPolicyResolver.resolve(context).perTurnSnapshot
        context.hasSelectedMember = true
        let resumed = DeepTutorToolPolicyResolver.resolveForMemberSelectionResume(
            context: context,
            originalUserPrompt: context.userInput,
            selectedMemberID: 42,
            priorSnapshot: prior
        )

        XCTAssertTrue(resumed.allowedToolNames.contains(SparkToolName.fetchSleepDetails.rawValue))
        XCTAssertFalse(resumed.allowedToolNames.contains(SparkToolName.requestMemberSelection.rawValue))
    }

    func testStepsSubdomainMountsStepToolOnly() {
        let context = makeContext(
            userInput: "看看我这周步数",
            capability: .chat,
            hasSelectedMember: true
        )
        let policy = DeepTutorToolPolicyResolver.resolve(context)
        XCTAssertEqual(
            policy.structuredIntents.first { $0.domain == .healthData }?.subdomain,
            .steps
        )
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.fetchStepDetails.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchSleepDetails.rawValue))
    }

    private func makeContext(
        userInput: String,
        capability: DeepTutorCapability,
        hasSelectedMember: Bool
    ) -> DeepTutorToolMountContext {
        var context = DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: UUID(),
            conversationTitle: "Test"
        )
        context.snapshotRequestedTools = []
        context.hasSelectedMember = hasSelectedMember
        context.healthDataCapabilityAvailable = true
        return context
    }
}
