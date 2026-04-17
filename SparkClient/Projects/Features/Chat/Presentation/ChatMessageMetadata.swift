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
    let taskCards: [TaskCard]
    /// 对话内结构化医疗卡片（用药/处方/检查/病历），见 ``ChatStreamFieldKey.structuredHealthCards``。
    let structuredHealthCards: StructuredHealthCardsBlob?

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
        taskCards = Self.decodeArray(type: ChatStreamFieldKey.taskCards, from: message)
        structuredHealthCards = Self.decodeObject(type: ChatStreamFieldKey.structuredHealthCards, from: message)
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
        if let rows = try? makeDecoder().decode([T].self, from: data) {
            return rows
        }
        // 兼容服务端返回单对象的情况，自动包装成数组，避免卡片丢失。
        if let single = try? makeDecoder().decode(T.self, from: data) {
            return [single]
        }
        return []
    }

    private static func decodeObject<T: Decodable>(type: String, from message: ChatMessage) -> T? {
        guard let raw = attachmentText(type: type, from: message),
              let data = raw.data(using: .utf8) else { return nil }
        return try? makeDecoder().decode(T.self, from: data)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) {
                return date
            }
            if let fallback = ISO8601DateFormatter().date(from: text) {
                return fallback
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date")
        }
        return decoder
    }
}
