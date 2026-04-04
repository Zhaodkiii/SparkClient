import Foundation

protocol AIRuntimeGateway: Sendable {
    func generateText(client: AIClient, messages: [AIRuntimeMessage]) async throws -> AIRuntimeTextResponse
}
