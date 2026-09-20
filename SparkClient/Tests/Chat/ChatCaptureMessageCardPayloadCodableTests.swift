#if canImport(XCTest)
import Foundation
import XCTest

final class ChatCaptureMessageCardPayloadCodableTests: XCTestCase {
    func testSupplementaryReportCaptureCardDecodesFromRemotePayload() throws {
        let block = try decodeCaptureBlock(cardType: "supplementary_report")

        XCTAssertEqual(block.kind, .captureCard)
        XCTAssertEqual(block.captureMessageCard?.cardType, .supplementaryReport)
        XCTAssertEqual(block.captureMessageCard?.uploadMode, .composer)
    }

    func testUnknownCaptureCardTypeDoesNotFailWholeBlockDecode() throws {
        let block = try decodeCaptureBlock(cardType: "future_capture_type")

        XCTAssertEqual(block.kind, .captureCard)
        XCTAssertEqual(block.captureMessageCard?.cardType, .unsupported("future_capture_type"))
    }

    private func decodeCaptureBlock(cardType: String) throws -> ChatMessageBlock {
        let json = """
        {
          "id": "8420e26f-41b2-4855-be1d-7259f2e73a8b",
          "kind": "captureCard",
          "status": "ready",
          "revision": 1,
          "order_key": 1000.0,
          "tool_call_id": null,
          "parent_tool_call_id": "doctor-report-eaabdbfa-8877-412e-84d6-2bf418ad06cd",
          "parent_block_id": null,
          "node_role": "toolPresentation",
          "anchor": null,
          "payload": {
            "capture_card": {
              "_0": {
                "id": "eaabdbfa-8877-412e-84d6-2bf418ad06cd",
                "status": "pending",
                "card_type": "\(cardType)",
                "created_at": "2026-09-19T23:47:59.957477+00:00",
                "updated_at": "2026-09-19T23:47:59.957477+00:00",
                "upload_mode": "composer",
                "source_tool_call_id": "doctor-report-eaabdbfa-8877-412e-84d6-2bf418ad06cd",
                "selected_attachments": []
              }
            }
          },
          "created_at": "2026-09-19T23:47:59.957477+00:00",
          "updated_at": "2026-09-19T23:47:59.957477+00:00"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)
    }
}
#endif
