import Foundation

final class OpenAICompatibleTextGateway: AIRuntimeGateway, @unchecked Sendable {
    private let session: URLSession
    private let logger: Logger
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        logger: Logger = ConsoleLogger()
    ) {
        self.session = session
        self.logger = logger
    }

    func generateText(client: AIClient, messages: [AIRuntimeMessage]) async throws -> AIRuntimeTextResponse {
        let payload = ChatCompletionRequest(
            model: client.model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: client.temperature,
            maxTokens: client.maxTokens,
            stream: false
        )

        var request = URLRequest(url: client.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = client.apiKey, apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIRuntimeError.invalidResponse
            }

            if (200 ..< 300).contains(httpResponse.statusCode) == false {
                throw AIRuntimeError.server(
                    statusCode: httpResponse.statusCode,
                    message: parseServerErrorMessage(from: data)
                )
            }

            let completion = try parseSuccessResponse(data: data)
            let usage = completion.usage
            let content = completion.choices.first?.message.normalizedContent ?? ""
            logger.debug(
                "AI 推理成功，model=\(completion.model), promptTokens=\(usage?.promptTokens ?? -1), completionTokens=\(usage?.completionTokens ?? -1)",
                category: "ai_runtime"
            )

            return AIRuntimeTextResponse(
                text: content,
                model: completion.model,
                promptTokens: usage?.promptTokens,
                completionTokens: usage?.completionTokens
            )
        } catch let urlError as URLError {
            throw AIRuntimeError.transport(urlError)
        }
    }

    private func parseSuccessResponse(data: Data) throws -> ChatCompletionResponse {
        if let wrapped = try? decoder.decode(BackendWrappedChatCompletionResponse.self, from: data), wrapped.code == 0 {
            return wrapped.data
        }
        return try decoder.decode(ChatCompletionResponse.self, from: data)
    }

    private func parseServerErrorMessage(from data: Data) -> String {
        if let wrapped = try? decoder.decode(BackendWrappedErrorResponse.self, from: data), wrapped.msg.isEmpty == false {
            return wrapped.msg
        }
        if let errorResponse = try? decoder.decode(OpenAIErrorEnvelope.self, from: data),
           let message = errorResponse.error?.message,
           message.isEmpty == false {
            return message
        }
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = jsonObject["message"] as? String,
           message.isEmpty == false {
            return message
        }
        return "AI 服务暂时不可用，请稍后重试。"
    }
}

private struct ChatCompletionRequest: Encodable {
    struct RequestMessage: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [RequestMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct ResponseMessage: Decodable {
            struct Part: Decodable {
                let type: String?
                let text: String?
            }

            let role: String?
            let contentString: String?
            let contentParts: [Part]?

            var normalizedContent: String {
                if let contentString, contentString.isEmpty == false {
                    return contentString
                }
                if let contentParts {
                    let text = contentParts.compactMap(\.text).joined(separator: "\n")
                    if text.isEmpty == false {
                        return text
                    }
                }
                return ""
            }

            enum CodingKeys: String, CodingKey {
                case role
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                role = try container.decodeIfPresent(String.self, forKey: .role)
                if let stringContent = try? container.decodeIfPresent(String.self, forKey: .content) {
                    contentString = stringContent
                    contentParts = nil
                } else {
                    contentString = nil
                    contentParts = try container.decodeIfPresent([Part].self, forKey: .content)
                }
            }
        }

        let message: ResponseMessage
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    let model: String
    let choices: [Choice]
    let usage: Usage?
}

private struct OpenAIErrorEnvelope: Decodable {
    struct OpenAIError: Decodable {
        let message: String?
    }

    let error: OpenAIError?
}

private struct BackendWrappedErrorResponse: Decodable {
    let code: Int
    let msg: String
}

private struct BackendWrappedChatCompletionResponse: Decodable {
    let code: Int
    let msg: String
    let data: ChatCompletionResponse
}
