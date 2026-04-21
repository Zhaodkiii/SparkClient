import Foundation

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let memberID: Int?
    let title: String
    let scenario: AIScenario
    let currentModelName: String?
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let maxMessages: Int
    let rolePrompt: String
    /// 持久化枚举 `ChatThreadImageDeliveryMode.rawValue`；`nil` 表示旧数据，按产品默认视为直发多模态。
    let imageDeliveryModeRaw: String?
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let serverUpdatedAt: Date?

    /// 与 ZDK 兼容：缺失时默认 `.directMultimodal`。
    var imageDeliveryMode: ChatThreadImageDeliveryMode {
        guard let raw = imageDeliveryModeRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return .directMultimodal
        }
        if let mode = ChatThreadImageDeliveryMode(rawValue: raw) {
            return mode
        }
        switch raw {
        case "direct_multimodal":
            return .directMultimodal
        case "local_ocr":
            return .localOCR
        default:
            return .directMultimodal
        }
    }

    nonisolated init(
        id: UUID = UUID(),
        memberID: Int? = nil,
        title: String,
        scenario: AIScenario = .chat,
        currentModelName: String? = nil,
        temperature: Double = 0.6,
        topP: Double = 1.0,
        maxTokens: Int = 4096,
        maxMessages: Int = 20,
        rolePrompt: String = "",
        imageDeliveryModeRaw: String? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.memberID = memberID
        self.title = title
        self.scenario = scenario
        self.currentModelName = currentModelName
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.maxMessages = max(maxMessages, 1)
        self.rolePrompt = rolePrompt
        self.imageDeliveryModeRaw = imageDeliveryModeRaw
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}
