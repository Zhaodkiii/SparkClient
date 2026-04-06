import Foundation

protocol AIRuntimeGateway: Sendable {
    func generateText(client: AIClient, request: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse
}
