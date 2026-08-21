#if canImport(XCTest)
import Foundation
import XCTest

final class ChatGuideQuestionGenerationRaceTests: XCTestCase {
    func testEffectiveStateTreatsLegacyPayloadAsPresetWhenQuestionsPresent() {
        let payload = ChatGuideCardPayload(
            schemaVersion: 1,
            generatedAt: Date(),
            memberID: nil,
            metricSections: [],
            questions: ChatGuideQuestionPreset.phaseOne,
            questionGeneration: nil
        )
        XCTAssertEqual(payload.effectiveQuestionGenerationState, .preset)
        XCTAssertFalse(payload.isShowingQuestionLoading)
    }

    func testEffectiveStateTreatsEmptyLegacyQuestionsAsGenerating() {
        let payload = ChatGuideCardPayload(
            schemaVersion: 2,
            generatedAt: Date(),
            memberID: 42,
            metricSections: [],
            questions: [],
            questionGeneration: ChatGuideQuestionGenerationMeta(
                state: .generating,
                source: "current_chat_ai",
                memberID: 42
            )
        )
        XCTAssertTrue(payload.isShowingQuestionLoading)
    }

    func testMemberMismatchFailsBelongToCheck() {
        var payload = ChatGuideCardPreviewFixtures.fullPayload
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: .generated,
            source: "current_chat_ai",
            memberID: 1,
            generatedAt: Date()
        )
        XCTAssertFalse(payload.questionsBelongTo(memberID: 2))
    }
}
#endif
