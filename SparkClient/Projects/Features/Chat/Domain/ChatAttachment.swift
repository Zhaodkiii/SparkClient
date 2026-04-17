import Foundation

struct ChatAttachment: Codable, Equatable, Sendable {
    let id: UUID
    let type: String
    let url: URL?
    let text: String?
    /// 消息上送 piggyback：仅图片 attachment 使用，用于同步线程图片送达方式。
    let imageDeliveryModeRaw: String?

    nonisolated init(
        id: UUID = UUID(),
        type: String,
        url: URL? = nil,
        text: String? = nil,
        imageDeliveryModeRaw: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.text = text
        self.imageDeliveryModeRaw = imageDeliveryModeRaw
    }
}

/// 对齐 AI_HLY `StreamData` 的字段键定义。
/// 说明：新项目统一仅保留一套标准键（不做历史兼容分支）。
enum ChatStreamFieldKey {
    static let toolContent = "toolContent"
    static let toolName = "toolName"
    static let knowledgeCard = "knowledge_card"
    static let locationsInfo = "locations_info"
    static let routeInfo = "route_info"
    static let healthInfo = "health_info"
    static let healthSleepVisualization = "health_sleep_viz"
    static let htmlContent = "htmlContent"
    static let operationalState = "operationalState"
    static let operationalDescription = "operationalDescription"
    static let translatedText = "translatedText"
    static let events = "events"
    static let taskCards = "task_cards"
}
