import Foundation

/// 聊天消息附件解析层：
/// - 将消息 `attachments` 解析为 UI 可直接消费的结构化数据；
/// - 避免在 `ChatView` 内部散落大量字符串匹配与 JSON 反序列化代码。
struct ChatMessageMetadata {
    let toolName: String?
    let toolContent: String?
    let operationalState: String?
    let operationalDescription: String?
    let knowledgeCards: [ChatKnowledgeCard]
    let translatedText: String?
    let htmlContent: String?
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
    let events: [ChatEventPayload]
    let healthCards: [ChatHealthCardPayload]
    let sleepVisualization: ChatHealthSleepModel?

    init(message: ChatMessage) {
        toolName = Self.attachmentText(type: ChatStreamFieldKey.toolName, from: message)
        toolContent = Self.attachmentText(type: ChatStreamFieldKey.toolContent, from: message)
        operationalState = Self.attachmentText(type: ChatStreamFieldKey.operationalState, from: message)
        operationalDescription = Self.attachmentText(type: ChatStreamFieldKey.operationalDescription, from: message)
        translatedText = Self.attachmentText(type: ChatStreamFieldKey.translatedText, from: message)
        htmlContent = Self.attachmentText(type: ChatStreamFieldKey.htmlContent, from: message)
        knowledgeCards = Self.decodeArray(type: ChatStreamFieldKey.knowledgeCard, from: message)
        locations = Self.decodeArray(type: ChatStreamFieldKey.locationsInfo, from: message)
        routes = Self.decodeArray(type: ChatStreamFieldKey.routeInfo, from: message)
        events = Self.decodeArray(type: ChatStreamFieldKey.events, from: message)
        healthCards = Self.decodeArray(type: ChatStreamFieldKey.healthInfo, from: message)
        sleepVisualization = Self.decodeObject(type: ChatStreamFieldKey.healthSleepVisualization, from: message)
    }

    private static func attachmentText(type: String, from message: ChatMessage) -> String? {
        let value = message.attachments.first(where: { $0.type == type })?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    private static func decodeArray<T: Decodable>(type: String, from message: ChatMessage) -> [T] {
        guard let raw = attachmentText(type: type, from: message),
              let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func decodeObject<T: Decodable>(type: String, from message: ChatMessage) -> T? {
        guard let raw = attachmentText(type: type, from: message),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
