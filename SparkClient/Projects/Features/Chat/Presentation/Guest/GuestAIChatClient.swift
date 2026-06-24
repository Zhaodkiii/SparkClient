import Foundation

protocol GuestAIChatClient: Sendable {
    func send(messages: [GuestChatMessage], config: GuestAIConfig) async throws -> String
}

enum GuestAIChatError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case invalidPayload
    case emptyReply
    case httpFailed(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return L10n.text("guest.ai.error.invalid_configuration")
        case .invalidResponse:
            return L10n.text("guest.ai.error.invalid_response")
        case .invalidPayload:
            return L10n.text("guest.ai.error.invalid_payload")
        case .emptyReply:
            return L10n.text("guest.ai.error.empty_reply")
        case .httpFailed(let code, let message):
            if message.isEmpty {
                return L10n.format("guest.ai.error.http_failed", code)
            }
            return L10n.format("guest.ai.error.http_failed_detail", code, message)
        }
    }
}
