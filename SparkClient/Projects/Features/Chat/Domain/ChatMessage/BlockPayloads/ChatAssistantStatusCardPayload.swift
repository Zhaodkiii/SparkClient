import Foundation

nonisolated enum ChatAssistantStatusCardType: String, Codable, Sendable {
    case interrupted
    case sendFailed
}

nonisolated struct ChatAssistantStatusCardPayload: Codable, Equatable, Sendable {
    let type: ChatAssistantStatusCardType
    let message: String

    init(type: ChatAssistantStatusCardType, message: String) {
        self.type = type
        self.message = message
    }
}
