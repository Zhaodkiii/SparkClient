import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let syncEngine: ChatSyncEngine
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase

    func execute(
        threadID: UUID?,
        patientID: UUID? = nil,
        userInput: String
    ) async throws -> ChatThreadSnapshot {
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let thread = try await resolveThread(existingThreadID: threadID, patientID: patientID, firstUserInput: sanitizedInput)

        let clientMessageID = UUID()
        _ = try await repository.appendMessage(
            threadID: thread.id,
            role: .user,
            kind: .text,
            content: sanitizedInput,
            attachments: [],
            clientMessageID: clientMessageID,
            serverMessageID: nil,
            deliveryState: .pending
        )

        let history = await repository.loadMessages(threadID: thread.id)
        let contextPatientID = thread.patientID ?? patientID
        let patientContextSummary: String
        if let contextPatientID {
            patientContextSummary = await buildPatientContextSummaryUseCase.execute(patientID: contextPatientID, limit: 6)
        } else {
            patientContextSummary = ""
        }

        let output = try await orchestrator.generateReply(
            userInput: sanitizedInput,
            history: history,
            patientContextSummary: patientContextSummary,
            patientID: contextPatientID
        )

        _ = try await repository.appendMessage(
            threadID: thread.id,
            role: .assistant,
            kind: output.kind,
            content: output.text,
            attachments: [],
            clientMessageID: UUID(),
            serverMessageID: nil,
            deliveryState: .pending
        )

        do {
            try await syncEngine.syncNow()
        } catch {
            // 本地消息已经持久化，后台可重试，主流程不阻断。
        }

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
                let created = await repository.createThread(
                    patientID: patientID,
                    title: title.isEmpty ? promptLocalizer.newThreadTitle() : title
                )
                await repository.setActiveThread(id: created.id)
                return created
            }
            return active
        }

        let title = String(firstUserInput.prefix(18))
        let created = await repository.createThread(
            patientID: patientID,
            title: title.isEmpty ? promptLocalizer.newThreadTitle() : title
        )
        await repository.setActiveThread(id: created.id)
        return created
    }
}
