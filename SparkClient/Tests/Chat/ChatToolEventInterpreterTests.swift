#if canImport(XCTest)
import Foundation
import XCTest

final class ChatToolEventInterpreterTests: XCTestCase {
    /// 知识卡由 `ToolHub` + `StructuredHealthCardMergeCoordinator` 异步合并，解释器不生成 `knowledge_card` 附件。
    func testCreateKnowledgeDocumentTraceDoesNotEmitKnowledgeCardFromInterpreter() {
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

        XCTAssertEqual(result.knowledgeCardAttachmentCount, 0)
        XCTAssertNil(result.attachments.first(where: { $0.type == .knowledgeCard }))
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
