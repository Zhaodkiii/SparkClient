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

    func generateText(client: AIClient, request runtimeRequest: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse {
        let start = Date()
        let (reasoningExtras, useSuffix, thinkOn) = OpenAIReasoningPayload.build(
            providerUppercased: runtimeRequest.providerCompanyUppercased,
            options: runtimeRequest.reasoning
        )
        var runtimeMessages = runtimeRequest.messages
        if useSuffix {
            runtimeMessages = OpenAIReasoningPayload.patchMessagesThinkSuffix(runtimeMessages, thinkSuffixEnabled: thinkOn)
        }

        let payload = ChatCompletionRequest(
            model: client.model,
            messages: runtimeMessages.map {
                .init(
                    role: $0.role.rawValue,
                    content: $0.content,
                    toolCalls: ($0.toolCalls ?? []).map {
                        .init(
                            id: $0.id,
                            type: "function",
                            function: .init(name: $0.name, arguments: $0.arguments)
                        )
                    }.nilIfEmpty,
                    toolCallID: $0.toolCallID,
                    name: $0.name
                )
            },
            temperature: client.temperature,
            maxTokens: client.maxTokens,
            stream: true,
            tools: runtimeRequest.tools.map {
                .init(
                    type: "function",
                    function: .init(
                        name: $0.name,
                        description: $0.summary,
                        parameters: .init(
                            type: "object",
                            properties: $0.properties.mapValues { encodeRequestToolProperty(from: $0) },
                            required: $0.required
                        )
                    )
                )
            }.nilIfEmpty,
            toolChoice: runtimeRequest.tools.isEmpty ? nil : runtimeRequest.toolChoice.rawValue
        )

        var request = URLRequest(url: client.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = client.apiKey, apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let requestBodyData = try encodeMergedRequestBody(base: payload, reasoningExtras: reasoningExtras)
        request.httpBody = requestBodyData
        let requestBodyText = String(data: requestBodyData, encoding: .utf8) ?? "<non-utf8>"
        logger.debug(
            "AI 网关请求开始，model=\(client.model), endpoint=\(client.endpoint.absoluteString), messages=\(runtimeRequest.messages.count), tools=\(runtimeRequest.tools.count), apiKeyPresent=\(client.apiKey?.isEmpty == false)",
            category: "ai_runtime"
        )
        logger.debug("AI 网关请求报文=\(truncate(requestBodyText, limit: 4000))", category: "ai_runtime")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIRuntimeError.invalidResponse
            }
            if (200 ..< 300).contains(httpResponse.statusCode) == false {
                let errorData = try await bytes.reduce(into: Data()) { partialResult, byte in
                    partialResult.append(byte)
                }
                let responseBodyText = String(data: errorData, encoding: .utf8) ?? "<non-utf8>"
                logger.debug(
                    "AI 网关响应报文，status=\(httpResponse.statusCode), body=\(truncate(responseBodyText, limit: 4000))",
                    category: "ai_runtime"
                )
                logger.warning(
                    "AI 网关返回非 2xx，status=\(httpResponse.statusCode), model=\(client.model)",
                    category: "ai_runtime"
                )
                throw AIRuntimeError.server(
                    statusCode: httpResponse.statusCode,
                    message: parseServerErrorMessage(from: errorData)
                )
            }

            let completion = try await parseStreamingOrSingleResponse(bytes: bytes)
            let usage = completion.usage
            let content = completion.message.normalizedContent
            let toolCalls = completion.message.toolCalls?.map {
                AIRuntimeToolCall(
                    id: $0.id ?? UUID().uuidString,
                    name: $0.function?.name ?? "",
                    arguments: $0.function?.arguments ?? "{}"
                )
            } ?? []
            logger.debug(
                "AI 推理成功，model=\(completion.model), promptTokens=\(usage?.promptTokens ?? -1), completionTokens=\(usage?.completionTokens ?? -1)",
                category: "ai_runtime"
            )
            logger.info(
                "AI 网关请求完成，model=\(completion.model), cost=\(format(Date().timeIntervalSince(start)))s",
                category: "ai_runtime"
            )

            let reasoningTrimmed = completion.reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
            return AIRuntimeTextResponse(
                text: content,
                reasoningText: reasoningTrimmed.isEmpty ? nil : reasoningTrimmed,
                model: completion.model,
                promptTokens: usage?.promptTokens,
                completionTokens: usage?.completionTokens,
                toolCalls: toolCalls,
                finishReason: completion.finishReason
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

    private func encodeMergedRequestBody(
        base: ChatCompletionRequest,
        reasoningExtras: OpenAIReasoningPayload.Extras?
    ) throws -> Data {
        let baseData = try encoder.encode(base)
        guard let reasoningExtras else { return baseData }
        let extraData = try encoder.encode(reasoningExtras)
        guard
            var baseObj = try JSONSerialization.jsonObject(with: baseData) as? [String: Any],
            let extraObj = try JSONSerialization.jsonObject(with: extraData) as? [String: Any]
        else {
            return baseData
        }
        for (key, value) in extraObj {
            if let dict = value as? [String: Any], dict.isEmpty { continue }
            baseObj[key] = value
        }
        return try JSONSerialization.data(withJSONObject: baseObj)
    }

    private func parseStreamingOrSingleResponse(bytes: URLSession.AsyncBytes) async throws -> ParsedCompletion {
        var sawStreamFrame = false
        var bufferedLines: [String] = []
        var content = ""
        var reasoningText = ""
        var toolCalls: [Int: PartialToolCall] = [:]
        var model = ""
        var finishReason: String?

        for try await line in bytes.lines {
            bufferedLines.append(line)
            guard line.hasPrefix("data: ") else { continue }
            sawStreamFrame = true
            let dataLine = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if dataLine == "[DONE]" { break }
            guard let frameData = dataLine.data(using: .utf8) else { continue }
            if let wrapped = try? decoder.decode(BackendWrappedStreamChunk.self, from: frameData), wrapped.code == 0 {
                merge(
                    streamChunk: wrapped.data,
                    content: &content,
                    reasoning: &reasoningText,
                    toolCalls: &toolCalls,
                    model: &model,
                    finishReason: &finishReason
                )
                continue
            }
            if let chunk = try? decoder.decode(StreamChunk.self, from: frameData) {
                merge(
                    streamChunk: chunk,
                    content: &content,
                    reasoning: &reasoningText,
                    toolCalls: &toolCalls,
                    model: &model,
                    finishReason: &finishReason
                )
            }
        }

        if sawStreamFrame {
            let message = ChatCompletionResponse.Choice.ResponseMessage(
                role: "assistant",
                contentString: content,
                contentParts: nil,
                toolCalls: toolCalls
                    .sorted(by: { $0.key < $1.key })
                    .map { index, call in
                        ChatCompletionResponse.Choice.ResponseMessage.ToolCall(
                            id: call.id,
                            type: "function",
                            function: .init(name: call.name, arguments: call.arguments),
                            index: index
                        )
                    }
            )
            return ParsedCompletion(
                model: model.isEmpty ? "unknown" : model,
                usage: nil,
                message: message,
                finishReason: finishReason,
                reasoningText: reasoningText
            )
        }

        let raw = bufferedLines.joined(separator: "\n")
        guard let data = raw.data(using: .utf8) else {
            throw AIRuntimeError.invalidResponse
        }
        let response = try parseSuccessResponse(data: data)
        guard let choice = response.choices.first else {
            throw AIRuntimeError.invalidResponse
        }
        return ParsedCompletion(
            model: response.model,
            usage: response.usage,
            message: choice.message,
            finishReason: choice.finishReason,
            reasoningText: ""
        )
    }

    private func merge(
        streamChunk: StreamChunk,
        content: inout String,
        reasoning: inout String,
        toolCalls: inout [Int: PartialToolCall],
        model: inout String,
        finishReason: inout String?
    ) {
        if streamChunk.model.isEmpty == false {
            model = streamChunk.model
        }
        guard let choice = streamChunk.choices.first else { return }
        if let deltaContent = choice.delta.contentString, deltaContent.isEmpty == false {
            content.append(deltaContent)
        }
        if let deltaReason = choice.delta.reasoningString, deltaReason.isEmpty == false {
            reasoning.append(deltaReason)
        }
        if let deltaToolCalls = choice.delta.toolCalls {
            for item in deltaToolCalls {
                guard let index = item.index else { continue }
                var accumulated = toolCalls[index] ?? PartialToolCall()
                if let id = item.id, id.isEmpty == false {
                    accumulated.id = id
                }
                if let name = item.function?.name, name.isEmpty == false {
                    accumulated.name = name
                }
                if let arguments = item.function?.arguments, arguments.isEmpty == false {
                    accumulated.arguments.append(arguments)
                }
                toolCalls[index] = accumulated
            }
        }
        if let reason = choice.finishReason, reason.isEmpty == false {
            finishReason = reason
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
        let content: String?
        let toolCalls: [RequestToolCall]?
        let toolCallID: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
            case name
        }
    }

    let model: String
    let messages: [RequestMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let tools: [RequestTool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }

        struct ResponseMessage: Decodable {
            struct Part: Decodable {
                let type: String?
                let text: String?
            }

            struct ToolCall: Decodable {
                struct FunctionCall: Decodable {
                    let name: String?
                    let arguments: String?
                }

                let id: String?
                let type: String?
                let function: FunctionCall?
                let index: Int?
            }

            let role: String?
            let contentString: String?
            let contentParts: [Part]?
            let toolCalls: [ToolCall]?

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
                case toolCalls = "tool_calls"
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
                toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            }

            init(
                role: String?,
                contentString: String?,
                contentParts: [Part]?,
                toolCalls: [ToolCall]?
            ) {
                self.role = role
                self.contentString = contentString
                self.contentParts = contentParts
                self.toolCalls = toolCalls
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

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ToolCall: Decodable {
                struct FunctionCall: Decodable {
                    let name: String?
                    let arguments: String?
                }

                let index: Int?
                let id: String?
                let type: String?
                let function: FunctionCall?
            }

            let contentString: String?
            let toolCalls: [ToolCall]?
            /// Some providers expose chain-of-thought as `reasoning_content` or `reasoning` on the delta.
            let reasoningString: String?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
                case reasoningContent = "reasoning_content"
                case reasoning
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                contentString = try container.decodeIfPresent(String.self, forKey: .content)
                toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
                let rc = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
                let r = try container.decodeIfPresent(String.self, forKey: .reasoning)
                reasoningString = rc ?? r
            }
        }

        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let model: String
    let choices: [Choice]
}

private struct BackendWrappedStreamChunk: Decodable {
    let code: Int
    let msg: String
    let data: StreamChunk
}

private struct RequestTool: Encodable {
    let type: String
    let function: RequestToolFunction
}

private struct RequestToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: RequestToolParameters
}

private struct RequestToolParameters: Encodable {
    let type: String
    let properties: [String: RequestToolProperty]
    let required: [String]
}

private final class RequestToolProperty: Encodable {
    let type: String
    let description: String
    let enumValues: [String]?
    let format: String?
    let properties: [String: RequestToolProperty]?
    let required: [String]?
    let items: RequestToolProperty?

    init(
        type: String,
        description: String,
        enumValues: [String]?,
        format: String?,
        properties: [String: RequestToolProperty]?,
        required: [String]?,
        items: RequestToolProperty?
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.format = format
        self.properties = properties
        self.required = required
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case format
        case properties
        case required
        case items
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(enumValues, forKey: .enumValues)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(properties, forKey: .properties)
        try c.encodeIfPresent(required, forKey: .required)
        try c.encodeIfPresent(items, forKey: .items)
    }
}

private func encodeRequestToolProperty(from p: AIRuntimeToolProperty) -> RequestToolProperty {
    RequestToolProperty(
        type: p.type,
        description: p.description,
        enumValues: p.enumValues,
        format: p.format,
        properties: p.objectProperties?.mapValues { encodeRequestToolProperty(from: $0) },
        required: p.objectRequired,
        items: p.arrayItems.map { encodeRequestToolProperty(from: $0) }
    )
}

private struct RequestToolCall: Encodable {
    struct FunctionCall: Encodable {
        let name: String
        let arguments: String
    }

    let id: String
    let type: String
    let function: FunctionCall
}

private struct PartialToolCall {
    var id: String = UUID().uuidString
    var name: String = ""
    var arguments: String = ""
}

private struct ParsedCompletion {
    let model: String
    let usage: ChatCompletionResponse.Usage?
    let message: ChatCompletionResponse.Choice.ResponseMessage
    let finishReason: String?
    let reasoningText: String
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
