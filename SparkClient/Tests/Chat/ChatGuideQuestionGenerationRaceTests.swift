#if canImport(XCTest)
import Foundation
import XCTest

final class ChatGuideQuestionGenerationRaceTests: XCTestCase {
    func testEffectiveStateTreatsLegacyPayloadAsPresetWhenQuestionsPresent() {
        let payload = ChatGuideCardPayload(
            schemaVersion: 1,
            generatedAt: Date(),
            memberId: nil,
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
            memberId: 42,
            metricSections: [],
            questions: [],
            questionGeneration: ChatGuideQuestionGenerationMeta(
                state: .generating,
                source: "current_chat_ai",
                memberId: 42
            )
        )
        XCTAssertTrue(payload.isShowingQuestionLoading)
    }

    func testMemberMismatchFailsBelongToCheck() {
        var payload = ChatGuideCardPreviewFixtures.fullPayload
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: .generated,
            source: "current_chat_ai",
            memberId: 1,
            generatedAt: Date()
        )
        XCTAssertFalse(payload.questionsBelongTo(memberID: 2))
    }
}
#endif
