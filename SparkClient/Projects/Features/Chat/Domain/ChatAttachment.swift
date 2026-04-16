import Foundation

struct ChatAttachment: Codable, Equatable, Sendable {
    let id: UUID
    let type: String
    let url: URL?
    let text: String?

    init(
        id: UUID = UUID(),
        type: String,
        url: URL? = nil,
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.text = text
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
    static let medicationCards = "medication_cards"
    static let prescriptionCards = "prescription_cards"
    static let examReportCards = "exam_report_cards"
    static let medicalCaseCards = "medical_case_cards"
    static let htmlContent = "htmlContent"
    static let operationalState = "operationalState"
    static let operationalDescription = "operationalDescription"
    static let translatedText = "translatedText"
    static let events = "events"
    static let taskCards = "task_cards"
}
