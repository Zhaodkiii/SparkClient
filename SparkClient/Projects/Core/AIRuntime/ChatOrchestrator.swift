import Foundation

struct ChatOrchestratorOutput: Sendable {
    let text: String
    let kind: ChatMessageKind
}

struct ChatOrchestrator: Sendable {
    let runtimeService: any AIRuntimeServing
    let toolHub: ToolHub
    let consentGate: ConsentGate

    func generateReply(
        userInput: String,
        history: [ChatMessage],
        patientContextSummary: String,
        patientID: UUID?
    ) async throws -> ChatOrchestratorOutput {
        let promptLocalizer = PromptLocalizer()

        let toolResult = await toolHub.runIfNeeded(userInput: userInput, patientID: patientID)
        if case .executed(let result) = toolResult {
            let modelConsent = consentGate.evaluate(result: result, destination: .model)
            let output = modelConsent.allowed
                ? result.outputText
                : """
                \(result.outputText)

                \(promptLocalizer.consentBlockedHint(reason: modelConsent.reason))
                """
            return ChatOrchestratorOutput(text: output, kind: .tool)
        }

        let runtimeMessages = makeRuntimeMessages(
            from: history,
            patientContextSummary: patientContextSummary
        )
        let response = try await runtimeService.generateText(
            request: AIRuntimeTextRequest(scenario: .chat, messages: runtimeMessages)
        )

        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
