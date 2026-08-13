import Foundation

nonisolated enum ChatWeatherConfigCardReason: String, Codable, Hashable, Sendable {
    case disabled
    case missingProvider
    case missingAPIKey
    case invalidEndpoint
    case unsupportedProvider
}

nonisolated struct ChatWeatherConfigCardPayload: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let reason: ChatWeatherConfigCardReason
    let title: String
    let message: String
    let actionTitle: String

    init(
        id: UUID = UUID(),
        reason: ChatWeatherConfigCardReason,
        title: String,
        message: String,
        actionTitle: String = "去配置天气"
    ) {
        self.id = id
        self.reason = reason
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
    }
}
