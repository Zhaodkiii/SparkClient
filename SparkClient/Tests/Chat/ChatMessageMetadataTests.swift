#if canImport(XCTest)
import Foundation
import XCTest

final class ChatMessageMetadataTests: XCTestCase {
    func testMetadataDecodesStructuredAttachments() throws {
        let cardsJSON = try json([
            ChatKnowledgeCard(title: "知识卡", content: "内容 A"),
        ])
        let locationsJSON = try json([
            ChatMapLocationPayload(name: "医院", latitude: 31.23, longitude: 121.47),
        ])
        let routesJSON = try json([
            ChatRoutePayload(summary: "步行路线", distance: "1.2km", duration: "18m", mode: "walk"),
        ])
        let eventsJSON = try json([
            ChatEventPayload(type: "calendar", title: "复诊", dateText: "2026-04-20", location: "门诊", notes: "携带报告"),
        ])
        let healthJSON = try json([
            ChatHealthCardPayload(title: "早餐", energyKilocalories: 320, proteinGrams: 18, carbohydratesGrams: 35, fatGrams: 10, dateText: "2026-04-13"),
        ])

        let message = ChatMessage(
            threadID: UUID(),
            role: .assistant,
            kind: .tool,
            content: "",
            attachments: [
                ChatAttachment(type: ChatStreamFieldKey.toolName, text: "query_location"),
                ChatAttachment(type: ChatStreamFieldKey.toolContent, text: "工具输出"),
                ChatAttachment(type: ChatStreamFieldKey.operationalState, text: "正在使用工具：query_location"),
                ChatAttachment(type: ChatStreamFieldKey.operationalDescription, text: "请求中"),
                ChatAttachment(type: ChatStreamFieldKey.translatedText, text: "translated result"),
                ChatAttachment(type: ChatStreamFieldKey.htmlContent, text: "<html>ok</html>"),
                ChatAttachment(type: ChatStreamFieldKey.knowledgeCard, text: cardsJSON),
                ChatAttachment(type: ChatStreamFieldKey.locationsInfo, text: locationsJSON),
                ChatAttachment(type: ChatStreamFieldKey.routeInfo, text: routesJSON),
                ChatAttachment(type: ChatStreamFieldKey.events, text: eventsJSON),
                ChatAttachment(type: ChatStreamFieldKey.healthInfo, text: healthJSON),
            ]
        )

        let metadata = ChatMessageMetadata(message: message)
        XCTAssertEqual(metadata.toolName, "query_location")
        XCTAssertEqual(metadata.toolContent, "工具输出")
        XCTAssertEqual(metadata.operationalState, "正在使用工具：query_location")
        XCTAssertEqual(metadata.operationalDescription, "请求中")
        XCTAssertEqual(metadata.translatedText, "translated result")
        XCTAssertEqual(metadata.htmlContent, "<html>ok</html>")

        XCTAssertEqual(metadata.knowledgeCards.count, 1)
        XCTAssertEqual(metadata.knowledgeCards.first?.title, "知识卡")
        XCTAssertEqual(metadata.locations.count, 1)
        XCTAssertEqual(metadata.locations.first?.name, "医院")
        XCTAssertEqual(metadata.routes.count, 1)
        XCTAssertEqual(metadata.routes.first?.mode, "walk")
        XCTAssertEqual(metadata.events.count, 1)
        XCTAssertEqual(metadata.events.first?.title, "复诊")
        XCTAssertEqual(metadata.healthCards.count, 1)
        XCTAssertEqual(metadata.healthCards.first?.energyKilocalories, 320)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            XCTFail("JSON 编码失败")
            return ""
        }
        return text
    }
}
#endif
