import Foundation

protocol AIRuntimeServing: Sendable {
    func generateText(request: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse
}

final class AIRuntimeService: AIRuntimeServing, @unchecked Sendable {
    private let configCenter: AIConfigCenter
    private let gateway: any AIRuntimeGateway
    private let logger: Logger

    init(
        configCenter: AIConfigCenter,
        gateway: any AIRuntimeGateway,
        logger: Logger = ConsoleLogger()
    ) {
        self.configCenter = configCenter
        self.gateway = gateway
        self.logger = logger
    }

    func generateText(request: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse {
        guard request.messages.isEmpty == false else {
            throw AIRuntimeError.emptyMessages
        }

        let resolved = try await configCenter.resolve(for: request.scenario)
        let client = AIClientFactory.makeClient(from: resolved)
        logger.debug(
            "准备调用 AI 推理，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model)",
            category: "ai_runtime"
        )
        return try await gateway.generateText(client: client, messages: request.messages)
    }
}
