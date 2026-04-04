import Foundation

struct ChatOrchestratorOutput: Sendable {
    let text: String
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
        patientID: UUID?
    ) async throws -> ChatOrchestratorOutput {
        let promptLocalizer = PromptLocalizer()
        logger.debug(
            "对话编排开始，history=\(history.count), patient=\(shortID(patientID)), inputLength=\(userInput.count)",
            category: "chat_orchestrator"
        )

        let toolResult = await toolHub.runIfNeeded(userInput: userInput, patientID: patientID)
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
            return ChatOrchestratorOutput(text: output, kind: .tool)
        }

        // 无工具命中时转入模型推理路径，显式记录入参规模，便于排查上下文膨胀问题。
        let runtimeMessages = makeRuntimeMessages(
            from: history,
            patientContextSummary: patientContextSummary
        )
        logger.debug(
            "进入 AI 推理路径，runtimeMessages=\(runtimeMessages.count), patientContextLength=\(patientContextSummary.count)",
            category: "chat_orchestrator"
        )
        let response: AIRuntimeTextResponse
        do {
            response = try await runtimeService.generateText(
                request: AIRuntimeTextRequest(scenario: .chat, messages: runtimeMessages)
            )
        } catch {
            logger.error("AI 推理路径失败：\(error.localizedDescription)", category: "chat_orchestrator")
            throw error
        }

        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            logger.warning("AI 返回空文本，已回退到默认兜底文案", category: "chat_orchestrator")
        }
        return ChatOrchestratorOutput(
            text: text.isEmpty ? promptLocalizer.fallbackAssistantText() : text,
            kind: .text
        )
    }

    private func makeRuntimeMessages(
        from history: [ChatMessage],
        patientContextSummary: String
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

        runtimeMessages.append(
            contentsOf: history.map {
                AIRuntimeMessage(role: $0.role.runtimeRole, content: $0.content)
            }
        )
        return runtimeMessages
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }
}
