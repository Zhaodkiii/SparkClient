#if canImport(XCTest)
import Foundation
import XCTest

final class OpenAIReasoningPayloadTests: XCTestCase {
    func testZhipuReasoningOnlyUsesOnOffSwitchWithoutDepthMenu() {
        XCTAssertFalse(ProviderRegistry.showsReasoningDepthMenu(for: "ZHIPUAI"))
        XCTAssertFalse(ProviderRegistry.usesHighMaxReasoningEffortUI(for: "ZHIPUAI"))
    }

    func testZhipuDisabledReasoningSendsExplicitThinkingDisabled() throws {
        let result = OpenAIReasoningBuilder.build(
            provider: "ZHIPUAI",
            options: .disabled
        )

        let object = try encodedJSONObject(from: result.extras)
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertNil(object["reasoning_effort"])
        XCTAssertNil(thinking["budget_tokens"])
    }

    func testZhipuEnabledReasoningSendsThinkingEnabledWithoutBudget() throws {
        let result = OpenAIReasoningBuilder.build(
            provider: "ZHIPUAI",
            options: AIRuntimeReasoningOptions(isEnabled: true, effortTier: 3)
        )

        let object = try encodedJSONObject(from: result.extras)
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertNil(thinking["budget_tokens"])
    }

    private func encodedJSONObject(from extras: OpenAIReasoningExtras?) throws -> [String: Any] {
        let extras = try XCTUnwrap(extras)
        let data = try JSONEncoder.default.encode(extras)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
#endif
