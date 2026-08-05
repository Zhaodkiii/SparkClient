import Foundation

/// Guest 模式 AI 聊天客户端：复用 Runtime 下游网关，不在 Feature 层手写 HTTP / SSE。
struct GuestAIRuntimeChatClient: GuestAIChatClient {
    private let gateway: any AIRuntimeGateway
    private let logger: Logger

    init(gateway: any AIRuntimeGateway, logger: Logger = ConsoleLogger()) {
        self.gateway = gateway
        self.logger = logger
    }

    func send(messages: [GuestChatMessage], config: GuestAIConfig) async throws -> String {
        guard config.isValid, let endpoint = config.chatCompletionsURL else {
            throw GuestAIChatError.invalidConfiguration
        }

        let resolvedConfig = AIResolvedConfig(
            endpoint: endpoint,
            model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: 0.7,
            maxTokens: 2048,
            source: .trialPolicy
        )
        let client = AIClientFactory.makeClient(from: resolvedConfig)
        let runtimeMessages = messages.map { message in
            AIRuntimeMessage(
                role: mapRole(message.role),
                content: message.text
            )
        }
        let request = AIRuntimeTextRequest(
            scenario: .chat,
            messages: runtimeMessages
        )

        logger.info("游客 AI Runtime 请求 \(config.logDescription)", module: .aiConfig)

        do {
            let stream = try await gateway.generateTextStream(client: client, request: request)
            let text = try await collectGuestReply(from: stream)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw GuestAIChatError.emptyReply
            }
            return trimmed
        } catch let error as GuestAIChatError {
            throw error
        } catch let error as AIRuntimeError {
            throw mapRuntimeError(error)
        }
    }

    private func mapRole(_ role: GuestChatMessage.Role) -> AIRuntimeRole {
        switch role {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
    }

    private func mapRuntimeError(_ error: AIRuntimeError) -> GuestAIChatError {
        switch error {
        case .invalidResponse:
            return .invalidResponse
        case .server(let statusCode, let message):
            return .httpFailed(code: statusCode, message: message)
        case .emptyOutput:
            return .emptyReply
        case .emptyMessages, .transport:
            return .invalidPayload
        }
    }

    private func collectGuestReply(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> String {
        var bufferedText = ""
        var completedText: String?
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                bufferedText.append(delta)
            case .completed(let response):
                completedText = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }
        return completedText ?? bufferedText
    }
}
