#if canImport(XCTest)
import Foundation
import XCTest

final class ChatToolEventInterpreterTests: XCTestCase {
    private struct KnowledgeCardDraft: Decodable, Equatable {
        let title: String
        let content: String
    }

    func testCreateKnowledgeDocumentTraceGeneratesKnowledgeCardAttachment() throws {
        let interpreter = ChatToolEventInterpreter(logger: ConsoleLogger())
        let toolTrace = """
        [1] create_knowledge_document
        {"title":"慢病随访总结","content":"## 随访计划\n- 两周后复诊"}
        """

        let result = interpreter.interpret(
            kind: .tool,
            text: "",
            toolName: "create_knowledge_document",
            toolContent: toolTrace
        )

        XCTAssertEqual(result.knowledgeCardAttachmentCount, 1)
        let attachment = try XCTUnwrap(result.attachments.first(where: { $0.type == .knowledgeCard }))
        let raw = try XCTUnwrap(attachment.text)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let cards = try JSONDecoder().decode([KnowledgeCardDraft].self, from: data)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.title, "慢病随访总结")
        XCTAssertEqual(cards.first?.content, "## 随访计划\n- 两周后复诊")
    }

    func testToolContentGeneratesOperationalAttachments() {
        let interpreter = ChatToolEventInterpreter(logger: ConsoleLogger())

        let result = interpreter.interpret(
            kind: .tool,
            text: "",
            toolName: "query_location",
            toolContent: "使用工具：query_location\nargs=latitude=31.23,longitude=121.47,keyword=医院"
        )

        let state = result.attachments.first(where: { $0.type == .operationalState })?.text
        let description = result.attachments.first(where: { $0.type == .operationalDescription })?.text

        XCTAssertEqual(state, "使用工具：query_location")
        XCTAssertEqual(description, "args=latitude=31.23,longitude=121.47,keyword=医院")
        XCTAssertGreaterThanOrEqual(result.toolAttachmentCount, 3)
    }
}
#endif
