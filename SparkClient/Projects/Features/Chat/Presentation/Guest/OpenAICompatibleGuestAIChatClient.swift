import Foundation

struct OpenAICompatibleGuestAIChatClient: GuestAIChatClient {
    private let logger: Logger
    private let session: URLSession

    init(logger: Logger = ConsoleLogger(), session: URLSession = .shared) {
        self.logger = logger
        self.session = session
    }

    func send(messages: [GuestChatMessage], config: GuestAIConfig) async throws -> String {
        guard config.isValid, let url = config.chatCompletionsURL else {
            throw GuestAIChatError.invalidConfiguration
        }

        logger.info("游客 AI 请求 \(config.logDescription)", module: .aiConfig)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages.map { message in
                [
                    "role": roleName(for: message.role),
                    "content": message.text,
                ]
            },
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GuestAIChatError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GuestAIChatError.httpFailed(code: http.statusCode, message: text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GuestAIChatError.invalidPayload
        }

        let content = extractAssistantText(from: json)
        guard content.isEmpty == false else {
            throw GuestAIChatError.emptyReply
        }
        return content
    }

    private func roleName(for role: GuestChatMessage.Role) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    private func extractAssistantText(from payload: [String: Any]) -> String {
        guard
            let choices = payload["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else { return "" }

        if let text = message["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }.joined()
            return joined.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
