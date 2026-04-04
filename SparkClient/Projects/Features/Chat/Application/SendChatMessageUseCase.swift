import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let runtimeService: any AIRuntimeServing
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase
    let toolHub: ToolHub
    let consentGate: ConsentGate

    func execute(
        threadID: UUID?,
        patientID: UUID? = nil,
        userInput: String
    ) async throws -> ChatThreadSnapshot {
        let promptLocalizer = PromptLocalizer()
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let thread = try await resolveThread(existingThreadID: threadID, patientID: patientID, firstUserInput: sanitizedInput)

        _ = try await repository.appendMessage(
            threadID: thread.id,
            role: .user,
            content: sanitizedInput
        )

        let toolResult = await toolHub.runIfNeeded(
            userInput: sanitizedInput,
            patientID: thread.patientID ?? patientID
        )
        if case .executed(let result) = toolResult {
            let modelConsent = consentGate.evaluate(result: result, destination: .model)
            let output = modelConsent.allowed
                ? result.outputText
                : """
                \(result.outputText)

                \(promptLocalizer.consentBlockedHint(reason: modelConsent.reason))
                """
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .assistant,
                content: output
            )
            guard let latestThread = await repository.loadThread(id: thread.id) else {
                throw ChatFeatureError.threadNotFound
            }
            let latestHistory = await repository.loadMessages(threadID: thread.id)
            return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
        }

        let history = await repository.loadMessages(threadID: thread.id)
        let contextPatientID = thread.patientID ?? patientID
        let patientContextSummary: String
        if let contextPatientID {
            patientContextSummary = await buildPatientContextSummaryUseCase.execute(patientID: contextPatientID, limit: 6)
        } else {
            patientContextSummary = ""
        }
        let runtimeMessages = makeRuntimeMessages(
            from: history,
            patientContextSummary: patientContextSummary
        )
        let response = try await runtimeService.generateText(
            request: AIRuntimeTextRequest(scenario: .chat, messages: runtimeMessages)
        )

        let assistantText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await repository.appendMessage(
            threadID: thread.id,
            role: .assistant,
            content: assistantText.isEmpty ? promptLocalizer.fallbackAssistantText() : assistantText
        )

        guard let latestThread = await repository.loadThread(id: thread.id) else {
            throw ChatFeatureError.threadNotFound
        }
        let latestHistory = await repository.loadMessages(threadID: thread.id)
        return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
    }

    private func resolveThread(
        existingThreadID: UUID?,
        patientID: UUID?,
        firstUserInput: String
    ) async throws -> ChatThread {
        let promptLocalizer = PromptLocalizer()
        if let existingThreadID {
            if let thread = await repository.loadThread(id: existingThreadID) {
                await repository.setActiveThread(id: existingThreadID)
                return thread
            }
            throw ChatFeatureError.threadNotFound
        }

        if let active = await repository.loadActiveThread() {
            if let patientID, active.patientID != patientID {
                let title = String(firstUserInput.prefix(18))
                return await repository.createThread(
                    patientID: patientID,
                    title: title.isEmpty ? promptLocalizer.newThreadTitle() : title
                )
            }
            return active
        }

        let title = String(firstUserInput.prefix(18))
        return await repository.createThread(
            patientID: patientID,
            title: title.isEmpty ? promptLocalizer.newThreadTitle() : title
        )
    }

    private func makeRuntimeMessages(
        from history: [ChatMessage],
        patientContextSummary: String
    ) -> [AIRuntimeMessage] {
        let promptLocalizer = PromptLocalizer()
        var runtimeMessages: [AIRuntimeMessage] = [
            AIRuntimeMessage(
                role: .system,
                content: promptLocalizer.chatSystemPrompt()
            )
        ]
        if patientContextSummary.isEmpty == false {
            runtimeMessages.append(
                AIRuntimeMessage(
                    role: .system,
                    content: patientContextSummary
                )
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
