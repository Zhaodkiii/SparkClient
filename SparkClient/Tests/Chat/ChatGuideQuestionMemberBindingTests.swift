#if canImport(XCTest)
import Foundation
import XCTest

final class ChatGuideQuestionMemberBindingTests: XCTestCase {
    func testInitialQuestionStateUsesPresetWhenUnboundAndDefaultBindingDisabled() {
        let state = ChatGuideCardPayloadBuilder.initialQuestionState(
            memberID: nil,
            defaultMemberBindingEnabled: false
        )
        XCTAssertEqual(state.questions, ChatGuideQuestionPreset.phaseOne)
        XCTAssertEqual(state.questionGeneration?.state, .preset)
    }

    func testInitialQuestionStateUsesGeneratingWhenDefaultBindingEnabled() {
        let state = ChatGuideCardPayloadBuilder.initialQuestionState(
            memberID: nil,
            defaultMemberBindingEnabled: true
        )
        XCTAssertTrue(state.questions.isEmpty)
        XCTAssertEqual(state.questionGeneration?.state, .generating)
    }

    func testQuestionsBelongToMemberID() {
        var payload = ChatGuideCardPreviewFixtures.generatingPayload
        payload.questionGeneration?.memberId = 42
        XCTAssertTrue(payload.questionsBelongTo(memberID: 42))
        XCTAssertFalse(payload.questionsBelongTo(memberID: 7))
    }

    func testLocateFirstGuideCardFindsSystemGuideMessage() {
        let payload = ChatGuideCardPreviewFixtures.generatingPayload
        let message = ChatGuideSystemMessageFactory.make(threadID: UUID(), payload: payload)
        let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: [message])
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.payload.questionGeneration?.state, .generating)
    }
}
#endif
