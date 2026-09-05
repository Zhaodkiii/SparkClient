#if canImport(XCTest)
import Foundation
import XCTest

final class HospitalFileGalleryPayloadCodableTests: XCTestCase {
    func testHospitalFileGalleryBlockDecodesAsFileAttachmentsKind() throws {
        let json = """
        {
          "id": "8ca0d851-54d0-4d19-8a71-7b8682363f97",
          "kind": "fileGallery",
          "status": "ready",
          "revision": 1,
          "order_key": 1200.0,
          "tool_call_id": null,
          "parent_tool_call_id": null,
          "parent_block_id": null,
          "node_role": "timeline",
          "anchor": null,
          "payload": {
            "file_gallery": {
              "_0": [{
                "id": "84eeb9cc-00fb-490e-9ea5-5a50ee011d5c",
                "url": "https://cdn.example.test/consult.pdf",
                "type": "document",
                "order": 0,
                "file_id": 2574,
                "filename": "存款人密码纸.pdf",
                "file_size": 113227,
                "mime_type": "application/pdf"
              }]
            }
          },
          "created_at": "2026-09-05T07:16:17.075177+00:00",
          "updated_at": "2026-09-05T07:16:17.075177+00:00"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)

        XCTAssertEqual(decoded.kind, .fileAttachments)
        XCTAssertEqual(decoded.attachments.count, 1)
        XCTAssertEqual(decoded.attachments[0].type, .pdf)
        XCTAssertEqual(decoded.attachments[0].fileId, 2574)
        XCTAssertEqual(
            decoded.attachments[0].url?.absoluteString,
            "https://cdn.example.test/consult.pdf"
        )
    }

    func testDocumentAttachmentTypeMapsToPDF() throws {
        let json = """
        {"id":"84eeb9cc-00fb-490e-9ea5-5a50ee011d5c","type":"document","url":"https://cdn.example.test/a.pdf"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder.chatRemote.decode(ChatAttachment.self, from: data)
        XCTAssertEqual(decoded.type, .pdf)
    }
}
#endif
