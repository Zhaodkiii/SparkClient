import Foundation

protocol AIRuntimeGateway: Sendable {
    func generateTextStream(
        client: AIClient,
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>
}
