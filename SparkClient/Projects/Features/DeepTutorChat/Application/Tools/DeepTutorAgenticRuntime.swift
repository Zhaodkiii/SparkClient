import Foundation

struct DeepTutorAgenticRuntime: Sendable {
    let runtimeService: any AIRuntimeServing
    let registry: DeepTutorToolRegistry
    let logger: Logger

    struct Request: Sendable {
        let messages: [AIRuntimeMessage]
        let systemPrompt: String
        let composition: DeepTutorToolRuntimeCompositionResult
        let context: DeepTutorToolContext
        let reasoning: AIRuntimeReasoningOptions
        let preferredModelName: String?
        let providerCompanyUppercased: String?
        let temperature: Double?
        let topP: Double?
        let maxTokens: Int?
        let cancellationToken: AIRuntimeCancellationToken?
        let onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)?
    }

    struct Response: Sendable {
        let output: ChatOrchestratorOutput
        let promptTokens: Int?
        let completionTokens: Int?
        let model: String
    }

    func run(_ request: Request) async throws -> Response {
        var loopMessages = request.messages
        let tools = request.composition.schemas
        let toolChoice: AIRuntimeToolChoice = tools.isEmpty ? .none : .auto
        var executedToolNames: [String] = []
        let maxRounds = 30
        let maxParallelToolCalls = 8

        for round in 1...maxRounds {
            try request.cancellationToken?.checkCancellation()
            let collected = try await collectRuntimeResponse(
                from: try await runtimeService.generateTextStream(
                    request: AIRuntimeTextRequest(
                        scenario: .chat,
                        messages: loopMessages,
                        tools: tools,
                        toolChoice: toolChoice,
                        reasoning: request.reasoning,
                        preferredModelName: request.preferredModelName,
                        providerCompanyUppercased: request.providerCompanyUppercased,
                        temperature: request.temperature,
                        topP: request.topP,
                        maxTokens: request.maxTokens,
                        cancellationToken: request.cancellationToken
                    )
                ),
                cancellationToken: request.cancellationToken,
                onPartial: request.onPartial
            )

            let response = collected.response
            if response.hasToolCalls == false {
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    throw AIRuntimeError.emptyOutput
                }
                return Response(
                    output: ChatOrchestratorOutput(
                        text: text,
                        reasoningText: response.reasoningText,
                        reasoningDurationMs: collected.reasoningDurationMs,
                        finishReason: response.finishReason,
                        kind: .text,
                        toolName: executedToolNames.last,
                        toolContent: executedToolNames.isEmpty ? nil : executedToolNames.joined(separator: ","),
                        blocks: []
                    ),
                    promptTokens: response.promptTokens,
                    completionTokens: response.completionTokens,
                    model: response.model
                )
            }

            let toolCalls = Array(response.toolCalls.prefix(maxParallelToolCalls))
            if DeepTutorDebugFlags.verboseChatStreamLogs {
                logger.info("DeepTutor tools requested, round=\(round), count=\(toolCalls.count)", module: DeepTutorChatLog.module)
            }
            loopMessages.append(
                AIRuntimeMessage(
                    role: .assistant,
                    content: response.text.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty,
                    toolCalls: toolCalls,
                    reasoningContent: response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty
                )
            )

            let duplicateOf = duplicateToolCalls(toolCalls)
            var paused = false
            for (index, call) in toolCalls.enumerated() {
                let arguments = DeepTutorToolArgumentDecoder.parse(call.arguments)
                let suppressUI = duplicateOf[index] != nil && call.name == DeepTutorToolName.askUser.rawValue
                if suppressUI == false {
                    await request.onPartial?(
                        ChatAssistantPartialDelta(
                            answer: response.text,
                            reasoning: response.reasoningText,
                            kind: .text,
                            toolName: call.name,
                            toolContent: nil,
                            toolArguments: call.arguments,
                            toolInvocationArguments: nil,
                            toolCallID: call.id
                        )
                    )
                }
                let result: DeepTutorToolResult
                if let primaryIndex = duplicateOf[index] {
                    result = duplicateResult(primaryCallID: toolCalls[primaryIndex].id, toolName: call.name)
                } else if paused && isPauseTool(call.name) {
                    result = duplicateResult(primaryCallID: "pending_user_input", toolName: call.name)
                } else {
                    result = await registry.execute(name: call.name, arguments: arguments, context: request.context)
                }
                executedToolNames.append(call.name)
                if suppressUI == false {
                    await request.onPartial?(
                        ChatAssistantPartialDelta(
                            answer: response.text,
                            reasoning: response.reasoningText,
                            kind: .tool,
                            toolName: call.name,
                            toolContent: result.content,
                            toolArguments: call.arguments,
                            toolInvocationArguments: result.metadata,
                            toolCallID: call.id
                        )
                    )
                }
                loopMessages.append(
                    AIRuntimeMessage(
                        role: .tool,
                        content: result.content,
                        toolCallID: call.id,
                        name: call.name
                    )
                )

                if result.pauseForUser != nil {
                    paused = true
                }
            }

            if paused {
                return Response(
                    output: ChatOrchestratorOutput(
                        text: response.text,
                        reasoningText: response.reasoningText,
                        reasoningDurationMs: collected.reasoningDurationMs,
                        finishReason: "awaiting_user_input",
                        kind: .tool,
                        toolName: executedToolNames.last,
                        toolContent: "awaiting_user_input",
                        blocks: []
                    ),
                    promptTokens: response.promptTokens,
                    completionTokens: response.completionTokens,
                    model: response.model
                )
            }
        }

        return Response(
            output: ChatOrchestratorOutput(
                text: "工具调用轮次已达到上限，请基于已有信息重新发起请求。",
                reasoningText: nil,
                reasoningDurationMs: nil,
                finishReason: "tool_round_limit",
                kind: .text,
                toolName: nil,
                toolContent: nil,
                blocks: []
            ),
            promptTokens: nil,
            completionTokens: nil,
            model: request.preferredModelName ?? "unknown"
        )
    }

    private func collectRuntimeResponse(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        cancellationToken: AIRuntimeCancellationToken?,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)?
    ) async throws -> CollectedRuntimeResponse {
        var bufferedText = ""
        var bufferedReasoning = ""
        var toolCallsByIndex: [Int: AIRuntimeToolCall] = [:]
        var completedResponse: AIRuntimeTextResponse?
        var firstReasoningAt: Date?
        var lastReasoningAt: Date?

        for try await event in stream {
            try cancellationToken?.checkCancellation()
            switch event {
            case .textDelta(let delta):
                bufferedText.append(delta)
                await onPartial?(
                    ChatAssistantPartialDelta(
                        answer: bufferedText,
                        reasoning: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty,
                        kind: .text,
                        toolName: nil,
                        toolContent: nil,
                        toolArguments: nil,
                        toolInvocationArguments: nil,
                        toolCallID: nil
                    )
                )
            case .reasoningDelta(let delta):
                let now = Date()
                if firstReasoningAt == nil { firstReasoningAt = now }
                lastReasoningAt = now
                bufferedReasoning.append(delta)
                await onPartial?(
                    ChatAssistantPartialDelta(
                        answer: bufferedText,
                        reasoning: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty,
                        kind: .text,
                        toolName: nil,
                        toolContent: nil,
                        toolArguments: nil,
                        toolInvocationArguments: nil,
                        toolCallID: nil
                    )
                )
            case .toolCallDelta(let delta):
                var call = toolCallsByIndex[delta.index] ?? AIRuntimeToolCall(
                    id: delta.id ?? UUID().uuidString,
                    name: delta.name ?? "",
                    arguments: ""
                )
                if let id = delta.id, id.isEmpty == false {
                    call = AIRuntimeToolCall(id: id, name: call.name, arguments: call.arguments)
                }
                if let name = delta.name, name.isEmpty == false {
                    call = AIRuntimeToolCall(id: call.id, name: name, arguments: call.arguments)
                }
                if let argumentsDelta = delta.argumentsDelta, argumentsDelta.isEmpty == false {
                    call = AIRuntimeToolCall(id: call.id, name: call.name, arguments: call.arguments + argumentsDelta)
                }
                toolCallsByIndex[delta.index] = call
                await onPartial?(
                    ChatAssistantPartialDelta(
                        answer: bufferedText,
                        reasoning: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty,
                        kind: .text,
                        toolName: call.name,
                        toolContent: nil,
                        toolArguments: call.arguments,
                        toolInvocationArguments: nil,
                        toolCallID: call.id
                    )
                )
            case .completed(let response):
                completedResponse = response
            }
        }

        let duration: Int64? = {
            guard let firstReasoningAt, let lastReasoningAt else { return nil }
            return Int64(lastReasoningAt.timeIntervalSince(firstReasoningAt) * 1000)
        }()
        if let completedResponse {
            return CollectedRuntimeResponse(response: completedResponse, reasoningDurationMs: duration)
        }
        return CollectedRuntimeResponse(
            response: AIRuntimeTextResponse(
                text: bufferedText,
                reasoningText: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).deepTutorAgenticNilIfEmpty,
                model: "unknown",
                promptTokens: nil,
                completionTokens: nil,
                toolCalls: toolCallsByIndex.keys.sorted().compactMap { toolCallsByIndex[$0] },
                finishReason: nil
            ),
            reasoningDurationMs: duration
        )
    }

    private struct CollectedRuntimeResponse: Sendable {
        let response: AIRuntimeTextResponse
        let reasoningDurationMs: Int64?
    }

    private func duplicateToolCalls(_ calls: [AIRuntimeToolCall]) -> [Int: Int] {
        var duplicateOf: [Int: Int] = [:]
        var seen: [String: Int] = [:]
        var firstAskUserIndex: Int?
        for (index, call) in calls.enumerated() {
            if call.name == DeepTutorToolName.askUser.rawValue {
                if let firstAskUserIndex {
                    duplicateOf[index] = firstAskUserIndex
                    continue
                }
                firstAskUserIndex = index
            }
            let key = "\(call.name)#\(normalizedArgumentsKey(call.arguments))"
            if let primary = seen[key] {
                duplicateOf[index] = primary
            } else {
                seen[key] = index
            }
        }
        return duplicateOf
    }

    private func normalizedArgumentsKey(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: normalized, encoding: .utf8) else {
            return raw
        }
        return text
    }

    private func duplicateResult(primaryCallID: String, toolName: String) -> DeepTutorToolResult {
        if toolName == DeepTutorToolName.askUser.rawValue {
            return DeepTutorToolResult(
                content: "(duplicate parallel ask_user tool_call - skipped. The earlier ask_user call with id=\(primaryCallID) is the only one that will pause for the user's reply. Ask all clarifying questions in one ask_user call's `questions` list; never emit multiple ask_user tool_calls in one assistant message.)",
                success: false
            )
        }
        return DeepTutorToolResult(
            content: "(duplicate parallel tool_call - skipped. The earlier call with id=\(primaryCallID) already ran in this batch; parallel calls must differ in arguments.)",
            success: false
        )
    }

    private func isPauseTool(_ name: String) -> Bool {
        name == DeepTutorToolName.askUser.rawValue
            || name == DeepTutorToolName.showCustomMessageCard.rawValue
            || name == DeepTutorToolName.requestMemberSelection.rawValue
    }
}

private extension String {
    var deepTutorAgenticNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
