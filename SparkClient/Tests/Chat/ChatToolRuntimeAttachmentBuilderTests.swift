#if canImport(XCTest)
import Foundation
import XCTest

final class ChatToolRuntimeAttachmentBuilderTests: XCTestCase {
    func testBuilderGeneratesToolAndOperationalAttachments() {
        let builder = ChatToolRuntimeAttachmentBuilder()

        let attachments = builder.build(
            toolName: "query_location",
            toolContent: "使用工具：query_location\nargs=latitude=31.23,longitude=121.47"
        )

        let types = attachments.map(\.type)
        XCTAssertTrue(types.contains(.toolName))
        XCTAssertTrue(types.contains(.toolContent))
        XCTAssertTrue(types.contains(.operationalState))
        XCTAssertTrue(types.contains(.operationalDescription))

        XCTAssertEqual(
            attachments.first(where: { $0.type == .operationalState })?.text,
            "使用工具：query_location"
        )
        XCTAssertEqual(
            attachments.first(where: { $0.type == .operationalDescription })?.text,
            "args=latitude=31.23,longitude=121.47"
        )
    }

    func testBuilderFallsBackToDefaultStateWhenNoPrefixLine() {
        let builder = ChatToolRuntimeAttachmentBuilder()

        let attachments = builder.build(
            toolName: "search_calendar_and_reminders",
            toolContent: "args=keyword=复诊"
        )

        XCTAssertEqual(
            attachments.first(where: { $0.type == .operationalState })?.text,
            "正在使用工具：search_calendar_and_reminders"
        )
    }
}
#endif
