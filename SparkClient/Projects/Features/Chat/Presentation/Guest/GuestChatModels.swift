import Foundation

struct GuestAIConfig: Equatable, Sendable {
    enum Provider: String, Sendable {
        case openAICompatible
    }

    let provider: Provider
    let baseURL: String
    let model: String
    let apiKey: String

    var isValid: Bool {
        chatCompletionsURL != nil
            && model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var chatCompletionsURL: URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = trimmedBase.isEmpty ? "https://api.openai.com/v1" : trimmedBase
        var normalized = resolvedBase.hasSuffix("/") ? String(resolvedBase.dropLast()) : resolvedBase
        if normalized.hasSuffix("/chat/completions") == false {
            normalized += "/chat/completions"
        }
        return URL(string: normalized)
    }

    var logDescription: String {
        "provider=\(provider.rawValue) model=\(model) baseURL=\(baseURL) apiKey=***"
    }
}

struct GuestChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}
