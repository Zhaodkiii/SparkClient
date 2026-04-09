import Foundation

import Foundation
import os

/// 最终类：OpenAI兼容格式的文本AI网关
/// 实现AIRuntimeGateway协议，用于处理流式/非流式的AI文本生成请求，适配OpenAI规范的接口
final class OpenAICompatibleTextGateway: AIRuntimeGateway, @unchecked Sendable {
    // MARK: - 私有属性
    /// 网络会话，用于发送HTTP请求
    private let session: URLSession
    /// 日志工具，记录请求、响应、错误等信息
    private let logger: Logger
    /// JSON编码器，用于序列化请求参数
    private let encoder = JSONEncoder()
    /// JSON解码器，用于解析响应数据
    private let decoder = JSONDecoder()

    // MARK: - 初始化方法
    /// 初始化网关
    /// - Parameters:
    ///   - session: 网络会话，默认使用系统共享会话
    ///   - logger: 日志实例，默认使用控制台日志
    init(
        session: URLSession = .shared,
        logger: Logger = ConsoleLogger()
    ) {
        self.session = session
        self.logger = logger
    }

    // MARK: - 核心方法：生成流式文本
    /// 生成AI流式文本响应（支持实时推送内容、推理过程、工具调用）
    /// - Parameters:
    ///   - client: AI客户端配置（模型、接口地址、API密钥等）
    ///   - runtimeRequest: 运行时请求参数（消息、工具、推理配置等）
    /// - Returns: 异步抛出流，持续推送AI响应事件
    func generateTextStream(
        client: AIClient,
        request runtimeRequest: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        // 记录请求开始时间
        let start = Date()
        // 构建推理相关的额外参数、后缀开关、思考开关
        let (reasoningExtras, useSuffix, thinkOn) = OpenAIReasoningPayload.build(
            providerUppercased: runtimeRequest.providerCompanyUppercased,
            options: runtimeRequest.reasoning
        )
        
        // 处理消息列表（根据开关添加思考后缀）
        var runtimeMessages = runtimeRequest.messages
        if useSuffix {
            runtimeMessages = OpenAIReasoningPayload.patchMessagesThinkSuffix(runtimeMessages, thinkSuffixEnabled: thinkOn)
        }
        
        // 构建OpenAI规范的聊天完成请求体
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
            stream: true, // 开启流式响应
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
        
        // 构建URLRequest请求对象
        var request = URLRequest(url: client.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 添加API密钥授权头
        if let apiKey = client.apiKey, apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // 合并基础请求体和推理额外参数，并编码为Data
        let requestBodyData = try encodeMergedRequestBody(base: payload, reasoningExtras: reasoningExtras)
        request.httpBody = requestBodyData
        
        // 日志：打印请求信息（截断超长报文）
        let requestBodyText = String(data: requestBodyData, encoding: .utf8) ?? "<non-utf8>"
        logger.debug(
            "AI 流式网关请求开始，model=\(client.model), endpoint=\(client.endpoint.absoluteString), messages=\(runtimeRequest.messages.count), tools=\(runtimeRequest.tools.count), apiKeyPresent=\(client.apiKey?.isEmpty == false)",
            category: "ai_runtime"
        )
        logger.debug("AI 流式网关请求报文=\(truncate(requestBodyText, limit: 4000))", category: "ai_runtime")

        // 返回异步抛出流，处理流式响应
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // 发送网络请求，获取异步字节流
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    // 校验响应类型
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIRuntimeError.invalidResponse
                    }
                    
                    // 校验HTTP状态码（200-299为成功）
                    if (200 ..< 300).contains(httpResponse.statusCode) == false {
                        // 读取错误响应数据
                        let errorData = try await bytes.reduce(into: Data()) { partialResult, byte in
                            partialResult.append(byte)
                        }
                        let responseBodyText = String(data: errorData, encoding: .utf8) ?? "<non-utf8>"
                        logger.debug(
                            "AI 流式网关响应报文，status=\(httpResponse.statusCode), body=\(truncate(responseBodyText, limit: 4000))",
                            category: "ai_runtime"
                        )
                        // 抛出服务端错误
                        throw AIRuntimeError.server(
                            statusCode: httpResponse.statusCode,
                            message: parseServerErrorMessage(from: errorData)
                        )
                    }

                    // 解析流式/非流式响应，持续推送事件
                    let completion = try await parseStreamingOrSingleResponse(bytes: bytes) { event in
                        continuation.yield(event)
                    }
                    
                    // 解析最终响应数据
                    let usage = completion.usage
                    let content = completion.message.normalizedContent
                    let toolCalls = completion.message.toolCalls?.map {
                        AIRuntimeToolCall(
                            id: $0.id ?? UUID().uuidString,
                            name: $0.function?.name ?? "",
                            arguments: $0.function?.arguments ?? "{}"
                        )
                    } ?? []
                    // 清理推理文本空白字符
                    let reasoningTrimmed = completion.reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 构建最终响应对象
                    let finalResponse = AIRuntimeTextResponse(
                        text: content,
                        reasoningText: reasoningTrimmed.isEmpty ? nil : reasoningTrimmed,
                        model: completion.model,
                        promptTokens: usage?.promptTokens,
                        completionTokens: usage?.completionTokens,
                        toolCalls: toolCalls,
                        finishReason: completion.finishReason
                    )
                    
                    // 推送完成事件，结束流
                    continuation.yield(.completed(finalResponse))
                    logger.info(
                        "AI 流式网关请求完成，model=\(completion.model), cost=\(format(Date().timeIntervalSince(start)))s",
                        category: "ai_runtime"
                    )
                    continuation.finish()
                } catch let urlError as URLError {
                    // 网络传输错误
                    continuation.finish(throwing: AIRuntimeError.transport(urlError))
                } catch {
                    // 其他未知错误
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - 私有工具方法
    /// 合并基础请求体和推理扩展参数，编码为JSON数据
    /// - Parameters:
    ///   - base: 基础请求体
    ///   - reasoningExtras: 推理相关扩展参数
    /// - Returns: 合并后的JSON数据
    private func encodeMergedRequestBody(
        base: ChatCompletionRequest,
        reasoningExtras: OpenAIReasoningPayload.Extras?
    ) throws -> Data {
        let baseData = try encoder.encode(base)
        // 无扩展参数直接返回基础数据
        guard let reasoningExtras else { return baseData }
        
        let extraData = try encoder.encode(reasoningExtras)
        // 转换为字典进行合并
        guard
            var baseObj = try JSONSerialization.jsonObject(with: baseData) as? [String: Any],
            let extraObj = try JSONSerialization.jsonObject(with: extraData) as? [String: Any]
        else {
            return baseData
        }
        
        // 合并非空的扩展参数
        for (key, value) in extraObj {
            if let dict = value as? [String: Any], dict.isEmpty { continue }
            baseObj[key] = value
        }
        
        return try JSONSerialization.data(withJSONObject: baseObj)
    }

    /// 解析流式响应或普通响应（自动兼容两种格式）
    /// - Parameters:
    ///   - bytes: 响应字节流
    ///   - onEvent: 解析到事件的回调
    /// - Returns: 解析完成的响应结果
    private func parseStreamingOrSingleResponse(
        bytes: URLSession.AsyncBytes,
        onEvent: ((AIRuntimeStreamEvent) -> Void)? = nil
    ) async throws -> ParsedCompletion {
        var sawStreamFrame = false // 是否识别到流式帧
        var bufferedLines: [String] = [] // 缓冲所有响应行
        // 解析结果缓存
        var content = ""
        var reasoningText = ""
        var toolCalls: [Int: PartialToolCall] = [:]
        var model = ""
        var finishReason: String?

        // 逐行读取流式响应
        for try await line in bytes.lines {
            bufferedLines.append(line)
            // 只处理data:开头的流式数据行
            guard line.hasPrefix("data: ") else { continue }
            sawStreamFrame = true
            
            // 提取数据内容
            let dataLine = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            // 结束标记
            if dataLine == "[DONE]" { break }
            guard let frameData = dataLine.data(using: .utf8) else { continue }
            
            // 解析包装格式的流式分片
            if let wrapped = try? decoder.decode(BackendWrappedStreamChunk.self, from: frameData), wrapped.code == 0 {
                merge(
                    streamChunk: wrapped.data,
                    content: &content,
                    reasoning: &reasoningText,
                    toolCalls: &toolCalls,
                    model: &model,
                    finishReason: &finishReason,
                    onEvent: onEvent
                )
                continue
            }
            
            // 解析原生OpenAI格式流式分片
            if let chunk = try? decoder.decode(StreamChunk.self, from: frameData) {
                merge(
                    streamChunk: chunk,
                    content: &content,
                    reasoning: &reasoningText,
                    toolCalls: &toolCalls,
                    model: &model,
                    finishReason: &finishReason,
                    onEvent: onEvent
                )
            }
        }

        // 处理流式响应结果
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

        // 未识别到流式帧，按普通响应解析
        let raw = bufferedLines.joined(separator: "\n")
        guard let data = raw.data(using: .utf8) else {
            throw AIRuntimeError.invalidResponse
        }
        let response = try parseSuccessResponse(data: data)
        guard let choice = response.choices.first else {
            throw AIRuntimeError.invalidResponse
        }
        
        // 推送普通响应的文本内容
        let fallbackContent = choice.message.normalizedContent
        if fallbackContent.isEmpty == false {
            onEvent?(.textDelta(fallbackContent))
        }
        
        return ParsedCompletion(
            model: response.model,
            usage: response.usage,
            message: choice.message,
            finishReason: choice.finishReason,
            reasoningText: ""
        )
    }

    /// 合并流式分片数据，更新解析缓存并推送事件
    /// - Parameters:
    ///   - streamChunk: 流式响应分片
    ///   - content: 文本内容缓存
    ///   - reasoning: 推理过程缓存
    ///   - toolCalls: 工具调用缓存
    ///   - model: 模型名称
    ///   - finishReason: 结束原因
    ///   - onEvent: 事件推送回调
    private func merge(
        streamChunk: StreamChunk,
        content: inout String,
        reasoning: inout String,
        toolCalls: inout [Int: PartialToolCall],
        model: inout String,
        finishReason: inout String?,
        onEvent: ((AIRuntimeStreamEvent) -> Void)?
    ) {
        // 更新模型名称
        if streamChunk.model.isEmpty == false {
            model = streamChunk.model
        }
        
        guard let choice = streamChunk.choices.first else { return }
        
        // 合并文本内容并推送事件
        if let deltaContent = choice.delta.contentString, deltaContent.isEmpty == false {
            content.append(deltaContent)
            onEvent?(.textDelta(deltaContent))
        }
        
        // 合并推理过程并推送事件
        if let deltaReason = choice.delta.reasoningString, deltaReason.isEmpty == false {
            reasoning.append(deltaReason)
            onEvent?(.reasoningDelta(deltaReason))
        }
        
        // 合并工具调用并推送事件
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
                onEvent?(
                    .toolCallDelta(
                        AIRuntimeToolCallDelta(
                            index: index,
                            id: item.id,
                            name: item.function?.name,
                            argumentsDelta: item.function?.arguments
                        )
                    )
                )
            }
        }
        
        // 更新结束原因
        if let reason = choice.finishReason, reason.isEmpty == false {
            finishReason = reason
        }
    }

    /// 解析成功的响应数据（兼容包装格式和原生格式）
    /// - Parameter data: 响应数据
    /// - Returns: 聊天完成响应
    private func parseSuccessResponse(data: Data) throws -> ChatCompletionResponse {
        if let wrapped = try? decoder.decode(BackendWrappedChatCompletionResponse.self, from: data), wrapped.code == 0 {
            return wrapped.data
        }
        return try decoder.decode(ChatCompletionResponse.self, from: data)
    }

    /// 解析服务端错误信息（兼容多种错误格式）
    /// - Parameter data: 错误响应数据
    /// - Returns: 错误提示文本
    private func parseServerErrorMessage(from data: Data) -> String {
        // 解析包装格式错误
        if let wrapped = try? decoder.decode(BackendWrappedErrorResponse.self, from: data), wrapped.msg.isEmpty == false {
            return wrapped.msg
        }
        // 解析OpenAI标准错误
        if let errorResponse = try? decoder.decode(OpenAIErrorEnvelope.self, from: data),
           let message = errorResponse.error?.message,
           message.isEmpty == false {
            return message
        }
        // 解析通用JSON错误
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = jsonObject["message"] as? String,
           message.isEmpty == false {
            return message
        }
        // 默认错误提示
        return "AI 服务暂时不可用，请稍后重试。"
    }

    /// 格式化时间间隔（保留3位小数）
    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    /// 截断超长文本，避免日志过大
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
