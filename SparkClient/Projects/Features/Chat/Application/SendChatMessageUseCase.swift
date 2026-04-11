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
        patientID: Int? = nil,
        userInput: String,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        onUserMessagePersisted: (@Sendable (_ snapshot: ChatThreadSnapshot) async -> Void)? = nil,
        onAssistantPartial: (@Sendable (_ answer: String, _ reasoning: String?, _ kind: ChatMessageKind) async -> Void)? = nil
    ) async throws -> ChatThreadSnapshot {
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let start = Date()
        logger.info(
            "sendMessage 开始，thread=\(shortID(threadID)), patient=\(shortID(patientID)), inputLength=\(sanitizedInput.count)",
            module: .general
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
                reasoningContent: nil,
                reasoningDurationMs: nil,
                reasoningExpanded: false,
                reasoningVisibility: .full,
                clientMessageID: clientMessageID,
                serverMessageID: nil,
                deliveryState: .pending
            )
            logger.debug(
                "用户消息已入库，thread=\(shortID(thread.id)), clientMessageID=\(shortID(clientMessageID))",
                module: .general
            )

            let history = await repository.loadMessages(threadID: thread.id)
            if let onUserMessagePersisted {
                await onUserMessagePersisted(
                    ChatThreadSnapshot(thread: thread, messages: history)
                )
            }
            let contextPatientID = thread.patientID ?? patientID
            let patientContextSummary: String
            if let contextPatientID {
                patientContextSummary = await buildPatientContextSummaryUseCase.execute(patientID: contextPatientID, limit: 6)
            } else {
                patientContextSummary = ""
            }
            logger.debug(
                "准备 AI 编排，thread=\(shortID(thread.id)), history=\(history.count), patientContextLength=\(patientContextSummary.count)",
                module: .general
            )

            let output = try await orchestrator.generateReply(
                userInput: sanitizedInput,
                history: history,
                patientContextSummary: patientContextSummary,
                patientID: contextPatientID,
                inference: inference,
                modelReasoning: modelReasoning
            )
            logger.info(
                "AI 编排完成，thread=\(shortID(thread.id)), kind=\(output.kind.rawValue), outputLength=\(output.text.count)",
                module: .general
            )

            if let onAssistantPartial {
                await streamAssistantReply(
                    output: output,
                    onPartial: onAssistantPartial
                )
            }

            let reasoningTrimmed = output.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .assistant,
                kind: output.kind,
                content: output.text,
                attachments: [],
                reasoningContent: reasoningTrimmed.flatMap { $0.isEmpty ? nil : $0 },
                reasoningDurationMs: nil,
                reasoningExpanded: false,
                reasoningVisibility: .full,
                clientMessageID: UUID(),
                serverMessageID: nil,
                deliveryState: .pending
            )

            do {
                try await syncEngine.pushOutboxOnly()
            } catch {
                // 本地消息已经持久化，后台可重试，主流程不阻断。
                logger.warning("消息上送失败，将由后台重试：\(error.localizedDescription)", module: .general)
            }

            guard let latestThread = await repository.loadThread(id: thread.id) else {
                throw ChatFeatureError.threadNotFound
            }
            let latestHistory = await repository.loadMessages(threadID: thread.id)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "sendMessage 完成，thread=\(shortID(thread.id)), messages=\(latestHistory.count), cost=\(format(cost))s",
                module: .general
            )
            return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error("sendMessage 失败，cost=\(format(cost))s error=\(error.localizedDescription)", module: .general)
            throw error
        }
    }

    private func resolveThread(
        existingThreadID: UUID?,
        patientID: Int?,
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

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private func streamAssistantReply(
        output: ChatOrchestratorOutput,
        onPartial: @Sendable (_ answer: String, _ reasoning: String?, _ kind: ChatMessageKind) async -> Void
    ) async {
        let kind = output.kind
        let reasoningFull = output.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reasoningFull.isEmpty == false {
            await emitStreamingChunks(reasoningFull) { partial in
                await onPartial("", partial.isEmpty ? nil : partial, kind)
            }
        }
        let trimmed = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            await onPartial("", reasoningFull.isEmpty ? nil : reasoningFull, kind)
            return
        }
        await emitStreamingChunks(trimmed) { partial in
            await onPartial(partial, reasoningFull.isEmpty ? nil : reasoningFull, kind)
        }
    }

    /// 即使上游当前是非流式返回，也在客户端按节流节奏增量落 UI，避免一次性大块刷新。
    private func emitStreamingChunks(
        _ text: String,
        onChunk: @Sendable (_ cumulative: String) async -> Void
    ) async {
        let scalars = Array(text)
        guard scalars.isEmpty == false else {
            await onChunk("")
            return
        }
        var built = ""
        var index = 0
        // 源头节流：把更新次数控制在合理上限，避免高频主线程刷新导致卡顿。
        let total = scalars.count
        let targetUpdateCount = min(90, max(18, Int(ceil(Double(total) / 22.0))))
        let minChunkSize = max(6, Int(ceil(Double(total) / Double(targetUpdateCount))))
        let emitDelayNanoseconds: UInt64 = 45_000_000

        while index < scalars.count {
            if Task.isCancelled { break }
            built.append(scalars[index])
            index += 1

            let reachedChunk = (index % minChunkSize == 0)
            let reachedTail = (index == scalars.count)
            if reachedChunk || reachedTail {
                await onChunk(built)
                if reachedTail == false {
                    try? await Task.sleep(nanoseconds: emitDelayNanoseconds)
                }
            }
        }
    }
}
