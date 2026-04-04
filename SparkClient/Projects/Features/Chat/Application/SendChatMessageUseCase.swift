import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let syncEngine: ChatSyncEngine
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase
    let logger: Logger

    init(
        repository: any ChatRepository,
        orchestrator: ChatOrchestrator,
        syncEngine: ChatSyncEngine,
        buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.orchestrator = orchestrator
        self.syncEngine = syncEngine
        self.buildPatientContextSummaryUseCase = buildPatientContextSummaryUseCase
        self.logger = logger
    }

    func execute(
        threadID: UUID?,
        patientID: UUID? = nil,
        userInput: String,
        onAssistantPartial: (@Sendable (_ partial: String, _ kind: ChatMessageKind) async -> Void)? = nil
    ) async throws -> ChatThreadSnapshot {
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let start = Date()
        logger.info(
            "sendMessage 开始，thread=\(shortID(threadID)), patient=\(shortID(patientID)), inputLength=\(sanitizedInput.count)",
            category: "chat_flow"
        )

        do {
            // 发送链路：用户消息落库 -> AI 编排 -> 助手消息落库 -> 尝试上送（失败不阻断主流程）。
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
            logger.debug(
                "用户消息已入库，thread=\(shortID(thread.id)), clientMessageID=\(shortID(clientMessageID))",
                category: "chat_flow"
            )

            let history = await repository.loadMessages(threadID: thread.id)
            let contextPatientID = thread.patientID ?? patientID
            let patientContextSummary: String
            if let contextPatientID {
                patientContextSummary = await buildPatientContextSummaryUseCase.execute(patientID: contextPatientID, limit: 6)
            } else {
                patientContextSummary = ""
            }
            logger.debug(
                "准备 AI 编排，thread=\(shortID(thread.id)), history=\(history.count), patientContextLength=\(patientContextSummary.count)",
                category: "chat_flow"
            )

            let output = try await orchestrator.generateReply(
                userInput: sanitizedInput,
                history: history,
                patientContextSummary: patientContextSummary,
                patientID: contextPatientID
            )
            logger.info(
                "AI 编排完成，thread=\(shortID(thread.id)), kind=\(output.kind.rawValue), outputLength=\(output.text.count)",
                category: "chat_flow"
            )

            if let onAssistantPartial {
                await streamAssistantReply(
                    output.text,
                    kind: output.kind,
                    onPartial: onAssistantPartial
                )
            }

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
                logger.warning("消息上送失败，将由后台重试：\(error.localizedDescription)", category: "chat_flow")
            }

            guard let latestThread = await repository.loadThread(id: thread.id) else {
                throw ChatFeatureError.threadNotFound
            }
            let latestHistory = await repository.loadMessages(threadID: thread.id)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "sendMessage 完成，thread=\(shortID(thread.id)), messages=\(latestHistory.count), cost=\(format(cost))s",
                category: "chat_flow"
            )
            return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error("sendMessage 失败，cost=\(format(cost))s error=\(error.localizedDescription)", category: "chat_flow")
            throw error
        }
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

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private func streamAssistantReply(
        _ text: String,
        kind: ChatMessageKind,
        onPartial: @Sendable (_ partial: String, _ kind: ChatMessageKind) async -> Void
    ) async {
        // 即使上游当前是非流式返回，也在客户端按节流节奏增量落 UI，避免一次性大块刷新。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            await onPartial("", kind)
            return
        }

        let scalars = Array(trimmed)
        var built = ""
        var index = 0
        var lastEmit = Date()
        let minEmitIntervalSeconds: TimeInterval = 0.07
        let minChunkSize = 14

        while index < scalars.count {
            built.append(scalars[index])
            index += 1

            let reachedChunk = (index % minChunkSize == 0) || index == scalars.count
            let reachedTime = Date().timeIntervalSince(lastEmit) >= minEmitIntervalSeconds
            if reachedChunk || reachedTime {
                await onPartial(built, kind)
                lastEmit = Date()
                try? await Task.sleep(nanoseconds: 28_000_000)
            }
        }
    }
}
