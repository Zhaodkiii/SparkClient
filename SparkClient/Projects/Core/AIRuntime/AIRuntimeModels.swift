import Foundation

enum AIRuntimeRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct AIRuntimeMessage: Codable, Equatable, Sendable {
    let role: AIRuntimeRole
    let content: String

    init(role: AIRuntimeRole, content: String) {
        self.role = role
        self.content = content
    }
}

struct AIRuntimeTextRequest: Sendable {
    let scenario: AIScenario
    let messages: [AIRuntimeMessage]

    init(scenario: AIScenario = .chat, messages: [AIRuntimeMessage]) {
        self.scenario = scenario
        self.messages = messages
    }
}

struct AIRuntimeTextResponse: Equatable, Sendable {
    let text: String
    let model: String
    let promptTokens: Int?
    let completionTokens: Int?
}

enum AIRuntimeError: LocalizedError {
    case emptyMessages
    case invalidResponse
    case transport(URLError)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyMessages:
            return "消息为空，无法调用 AI 推理。"
        case .invalidResponse:
            return "AI 返回结果不可解析。"
        case .transport(let error):
            return error.localizedDescription
        case .server(_, let message):
            return message
        }
    }
}
