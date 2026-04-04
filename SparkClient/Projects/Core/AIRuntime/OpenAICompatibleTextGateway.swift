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
        let start = Date()
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
        let requestBodyData = try encoder.encode(payload)
        request.httpBody = requestBodyData
        let requestBodyText = String(data: requestBodyData, encoding: .utf8) ?? "<non-utf8>"
        logger.debug(
            "AI 网关请求开始，model=\(client.model), endpoint=\(client.endpoint.absoluteString), messages=\(messages.count), apiKeyPresent=\(client.apiKey?.isEmpty == false)",
            category: "ai_runtime"
        )
        logger.debug("AI 网关请求报文=\(truncate(requestBodyText, limit: 4000))", category: "ai_runtime")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIRuntimeError.invalidResponse
            }
            let responseBodyText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            logger.debug(
                "AI 网关响应报文，status=\(httpResponse.statusCode), body=\(truncate(responseBodyText, limit: 4000))",
                category: "ai_runtime"
            )

            if (200 ..< 300).contains(httpResponse.statusCode) == false {
                logger.warning(
                    "AI 网关返回非 2xx，status=\(httpResponse.statusCode), model=\(client.model)",
                    category: "ai_runtime"
                )
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
            logger.info(
                "AI 网关请求完成，model=\(completion.model), cost=\(format(Date().timeIntervalSince(start)))s",
                category: "ai_runtime"
            )

            return AIRuntimeTextResponse(
                text: content,
                model: completion.model,
                promptTokens: usage?.promptTokens,
                completionTokens: usage?.completionTokens
            )
        } catch let urlError as URLError {
            logger.error(
                "AI 网关网络失败，model=\(client.model), code=\(urlError.code.rawValue), error=\(urlError.localizedDescription)",
                category: "ai_runtime"
            )
            throw AIRuntimeError.transport(urlError)
        } catch {
            logger.error("AI 网关处理失败，model=\(client.model), error=\(error.localizedDescription)", category: "ai_runtime")
            throw error
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

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return "\(text.prefix(limit))...(truncated)"
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
