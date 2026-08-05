#if canImport(XCTest)
import Foundation
import XCTest

final class GuestAIRuntimeChatClientTests: XCTestCase {
    func testInvalidConfigurationThrowsBeforeGatewayCall() async {
        let client = GuestAIRuntimeChatClient(gateway: StubAIRuntimeGateway())
        let config = GuestAIConfig(
            provider: .openAICompatible,
            baseURL: "",
            model: "",
            apiKey: ""
        )

        do {
            _ = try await client.send(messages: [], config: config)
            XCTFail("Expected invalidConfiguration")
        } catch let error as GuestAIChatError {
            XCTAssertEqual(error.errorDescription, GuestAIChatError.invalidConfiguration.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCollectsCompletedResponseText() async throws {
        let gateway = StubAIRuntimeGateway { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Hello"))
                continuation.yield(
                    .completed(
                        AIRuntimeTextResponse(
                            text: "Hello world",
                            reasoningText: nil,
                            model: "guest-model",
                            promptTokens: nil,
                            completionTokens: nil,
                            toolCalls: [],
                            finishReason: "stop"
                        )
                    )
                )
                continuation.finish()
            }
        }
        let client = GuestAIRuntimeChatClient(gateway: gateway)
        let config = GuestAIConfig(
            provider: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "test-key"
        )
        let messages = [GuestChatMessage(role: .user, text: "Hi")]

        let reply = try await client.send(messages: messages, config: config)
        XCTAssertEqual(reply, "Hello world")
    }

    func testMapsServerErrorToGuestHTTPFailed() async {
        let gateway = StubAIRuntimeGateway { _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: AIRuntimeError.server(statusCode: 401, message: "unauthorized"))
            }
        }
        let client = GuestAIRuntimeChatClient(gateway: gateway)
        let config = GuestAIConfig(
            provider: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "test-key"
        )

        do {
            _ = try await client.send(messages: [GuestChatMessage(role: .user, text: "Hi")], config: config)
            XCTFail("Expected httpFailed")
        } catch let error as GuestAIChatError {
            if case .httpFailed(let code, let message) = error {
                XCTAssertEqual(code, 401)
                XCTAssertEqual(message, "unauthorized")
            } else {
                XCTFail("Unexpected guest error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubAIRuntimeGateway: AIRuntimeGateway {
    let handler: @Sendable (AIClient, AIRuntimeTextRequest) -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>

    init(
        handler: @escaping @Sendable (AIClient, AIRuntimeTextRequest) -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> = { _, _ in
            AsyncThrowingStream { $0.finish() }
        }
    ) {
        self.handler = handler
    }

    func generateTextStream(
        client: AIClient,
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        handler(client, request)
    }
}
#endif
