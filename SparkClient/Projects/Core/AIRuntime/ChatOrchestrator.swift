import Foundation

struct ChatOrchestratorOutput: Sendable {
    let text: String
    let reasoningText: String?
    let kind: ChatMessageKind
}

struct ChatOrchestrator: Sendable {
    let runtimeService: any AIRuntimeServing
    let toolHub: ToolHub
    let consentGate: ConsentGate
    let logger: Logger

    init(
        runtimeService: any AIRuntimeServing,
        toolHub: ToolHub,
        consentGate: ConsentGate,
        logger: Logger = ConsoleLogger()
    ) {
        self.runtimeService = runtimeService
        self.toolHub = toolHub
        self.consentGate = consentGate
        self.logger = logger
    }

    func generateReply(
        userInput: String,
        history: [ChatMessage],
        patientContextSummary: String,
        patientID: Int?,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown
    ) async throws -> ChatOrchestratorOutput {
        let promptLocalizer = PromptLocalizer()
        let reasoningOpts = buildRuntimeReasoningOptions(inference: inference, model: modelReasoning)
        logger.debug(
            "对话编排开始，history=\(history.count), patient=\(shortID(patientID)), inputLength=\(userInput.count), tools=\(inference.useTools), knowledge=\(inference.useKnowledgeBag), web=\(inference.useWebSearch), reasoning=\(reasoningOpts.isEnabled), promptFallback=\(reasoningOpts.usePromptFallback)",
            category: "chat_orchestrator"
        )

        let toolResult: ToolHubResult
        if inference.useTools {
            toolResult = await toolHub.runIfNeeded(userInput: userInput, patientID: patientID)
        } else {
            toolResult = .none
        }
        if case .executed(let result) = toolResult {
            let modelConsent = consentGate.evaluate(result: result, destination: .model)
            logger.info(
                "工具调用已命中，tool=\(result.toolName), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive), consentAllowed=\(modelConsent.allowed)",
                category: "chat_orchestrator"
            )
            let output = modelConsent.allowed
                ? result.outputText
                : """
                \(result.outputText)

                \(promptLocalizer.consentBlockedHint(reason: modelConsent.reason))
                """
            return ChatOrchestratorOutput(text: output, reasoningText: nil, kind: .tool)
        }

        // 无工具命中时转入模型推理路径，显式记录入参规模，便于排查上下文膨胀问题。
        let runtimeMessages = makeRuntimeMessages(
            from: history,
            patientContextSummary: patientContextSummary,
            reasoning: reasoningOpts
        )
        let toolDefinitions = filteredToolDefinitions(inference: inference)
        let toolChoice: AIRuntimeToolChoice = inference.useTools && toolDefinitions.isEmpty == false ? .auto : .none
        logger.debug(
            "进入 AI 推理路径，runtimeMessages=\(runtimeMessages.count), patientContextLength=\(patientContextSummary.count), tools=\(toolDefinitions.count), toolChoice=\(String(describing: toolChoice))",
            category: "chat_orchestrator"
        )
        var loopMessages = runtimeMessages
        let maxToolRounds = 3
        var round = 0

        while round < maxToolRounds {
            round += 1
            let response: AIRuntimeTextResponse
            do {
                response = try await collectRuntimeResponse(
                    from: try await runtimeService.generateTextStream(
                        request: AIRuntimeTextRequest(
                            scenario: .chat,
                            messages: loopMessages,
                            tools: toolDefinitions,
                            toolChoice: toolChoice,
                            reasoning: reasoningOpts,
                            providerCompanyUppercased: nil
                        )
                    )
                )
            } catch {
                logger.error("AI 推理路径失败：\(error.localizedDescription)", category: "chat_orchestrator")
                throw error
            }

            if response.hasToolCalls == false {
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    logger.warning("AI 返回空文本，已回退到默认兜底文案", category: "chat_orchestrator")
                }
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text.isEmpty ? promptLocalizer.fallbackAssistantText() : text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    kind: .text
                )
            }

            if inference.useTools == false || toolDefinitions.isEmpty {
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text.isEmpty ? promptLocalizer.fallbackAssistantText() : text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    kind: .text
                )
            }

            logger.info(
                "模型返回 tool_calls，round=\(round), count=\(response.toolCalls.count)",
                category: "chat_orchestrator"
            )
            loopMessages.append(
                AIRuntimeMessage(role: .assistant, content: nil, toolCalls: response.toolCalls)
            )
            for call in response.toolCalls {
                let toolResult = await toolHub.executeToolCall(
                    name: call.name,
                    arguments: call.arguments,
                    patientID: patientID
                )
                let modelConsent = consentGate.evaluate(result: toolResult, destination: .model)
                let content = modelConsent.allowed
                    ? toolResult.outputText
                    : promptLocalizer.consentBlockedHint(reason: modelConsent.reason)
                loopMessages.append(
                    AIRuntimeMessage(
                        role: .tool,
                        content: content,
                        toolCallID: call.id,
                        name: call.name
                    )
                )
            }
        }

        logger.warning("工具调用超过最大轮次，回退兜底文案", category: "chat_orchestrator")
        return ChatOrchestratorOutput(text: promptLocalizer.fallbackAssistantText(), reasoningText: nil, kind: .text)
    }

    private func buildRuntimeReasoningOptions(
        inference: ChatOrchestratorInferenceOptions,
        model: ChatModelReasoningContext
    ) -> AIRuntimeReasoningOptions {
        let userWants = inference.reasoningEnabled
        let tier = inference.reasoningEffortTier
        if model.supportsReasoning {
            if model.reasoningControllable {
                return AIRuntimeReasoningOptions(
                    isEnabled: userWants,
                    effortTier: tier,
                    usePromptFallback: false
                )
            }
            return AIRuntimeReasoningOptions(
                isEnabled: true,
                effortTier: tier,
                usePromptFallback: false
            )
        }
        return AIRuntimeReasoningOptions(
            isEnabled: userWants,
            effortTier: tier,
            usePromptFallback: userWants
        )
    }

    private func makeRuntimeMessages(
        from history: [ChatMessage],
        patientContextSummary: String,
        reasoning: AIRuntimeReasoningOptions
    ) -> [AIRuntimeMessage] {
        let promptLocalizer = PromptLocalizer()
        var runtimeMessages: [AIRuntimeMessage] = [
            AIRuntimeMessage(role: .system, content: promptLocalizer.chatSystemPrompt())
        ]

        if patientContextSummary.isEmpty == false {
            runtimeMessages.append(
                AIRuntimeMessage(role: .system, content: patientContextSummary)
            )
        }

        if reasoning.usePromptFallback {
            runtimeMessages.append(
                AIRuntimeMessage(role: .system, content: promptLocalizer.deepThinkingInstruction())
            )
        }

        runtimeMessages.append(
            contentsOf: history.map {
                AIRuntimeMessage(role: $0.role.runtimeRole, content: $0.content)
            }
        )
        return runtimeMessages
    }

    private func filteredToolDefinitions(inference: ChatOrchestratorInferenceOptions) -> [AIRuntimeToolDefinition] {
        guard inference.useTools else { return [] }
        var definitions = toolHub.toolDefinitions()
        if inference.useKnowledgeBag == false {
            definitions.removeAll {
                $0.name == SparkToolName.searchKnowledgeBag || $0.name == SparkToolName.createKnowledgeDocument
            }
        }
        if inference.useWebSearch == false {
            let web: Set<String> = [
                SparkToolName.searchOnline,
                SparkToolName.readWebPage,
                SparkToolName.searchArxivPapers,
                SparkToolName.extractRemoteFileContent
            ]
            definitions.removeAll { web.contains($0.name) }
        }
        return definitions
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func collectRuntimeResponse(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> AIRuntimeTextResponse {
        var bufferedText = ""
        var bufferedReasoning = ""
        var toolCallsByIndex: [Int: AIRuntimeToolCall] = [:]
        var completedResponse: AIRuntimeTextResponse?

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                bufferedText.append(delta)
            case .reasoningDelta(let delta):
                bufferedReasoning.append(delta)
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
            case .completed(let response):
                completedResponse = response
            }
        }

        if let completedResponse {
            return completedResponse
        }

        let reasoningText = bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIRuntimeTextResponse(
            text: bufferedText,
            reasoningText: reasoningText.isEmpty ? nil : reasoningText,
            model: "unknown",
            promptTokens: nil,
            completionTokens: nil,
            toolCalls: toolCallsByIndex.keys.sorted().compactMap { toolCallsByIndex[$0] },
            finishReason: nil
        )
    }
}
