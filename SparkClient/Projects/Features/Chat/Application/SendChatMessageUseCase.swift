import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let syncEngine: ChatSyncEngine
    let buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase
    let toolEventInterpreter: ChatToolEventInterpreter
    let logger: Logger

    init(
        repository: any ChatRepository,
        orchestrator: ChatOrchestrator,
        syncEngine: ChatSyncEngine,
        buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase,
        toolEventInterpreter: ChatToolEventInterpreter? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.orchestrator = orchestrator
        self.syncEngine = syncEngine
        self.buildMemberContextSummaryUseCase = buildMemberContextSummaryUseCase
        self.logger = logger
        self.toolEventInterpreter = toolEventInterpreter ?? ChatToolEventInterpreter(logger: logger)
    }

    func execute(
        threadID: UUID?,
        memberID: Int? = nil,
        userInput: String,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        onUserMessagePersisted: (@Sendable (_ snapshot: ChatThreadSnapshot) async -> Void)? = nil,
        onAssistantPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil
    ) async throws -> ChatThreadSnapshot {
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let start = Date()
        logger.info(
            "sendMessage 开始，thread=\(shortID(threadID)), member=\(shortID(memberID)), inputLength=\(sanitizedInput.count)",
            module: .general
        )

        do {
            // 发送链路：用户消息落库 -> AI 编排 -> 助手消息落库 -> 尝试上送（失败不阻断主流程）。
            let thread = try await resolveThread(existingThreadID: threadID, memberID: memberID, firstUserInput: sanitizedInput)

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

            let history = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            if let onUserMessagePersisted {
                await onUserMessagePersisted(
                    ChatThreadSnapshot(thread: thread, messages: history)
                )
            }
            let contextMemberID = thread.memberID ?? memberID
            let memberContextSummary: String
            if let contextMemberID {
                memberContextSummary = await buildMemberContextSummaryUseCase.execute(memberID: contextMemberID, limit: 6)
            } else {
                memberContextSummary = ""
            }
            logger.debug(
                "准备 AI 编排，thread=\(shortID(thread.id)), history=\(history.count), memberContextLength=\(memberContextSummary.count)",
                module: .general
            )

            let output = try await orchestrator.generateReply(
                userInput: sanitizedInput,
                history: history,
                memberContextSummary: memberContextSummary,
                memberID: contextMemberID,
                inference: inference,
                modelReasoning: modelReasoning,
                onPartial: onAssistantPartial
            )
            logger.info(
                "AI 编排完成，thread=\(shortID(thread.id)), kind=\(output.kind.rawValue), outputLength=\(output.text.count)",
                module: .general
            )

            let reasoningTrimmed = output.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let interpreted = toolEventInterpreter.interpret(
                kind: output.kind,
                text: output.text,
                toolName: output.toolName,
                toolContent: output.toolContent
            )
            if interpreted.knowledgeCardAttachmentCount > 0 {
                // 这里生成的是“预览卡片附件”，不是最终知识库落库动作。
                logger.debug(
                    "已生成知识卡预览附件，thread=\(shortID(thread.id)), count=\(interpreted.knowledgeCardAttachmentCount)",
                    module: .general
                )
            }
            if interpreted.richAttachmentCount > 0 {
                logger.debug(
                    "已生成富卡片附件，thread=\(shortID(thread.id)), count=\(interpreted.richAttachmentCount)",
                    module: .general
                )
            }
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .assistant,
                kind: output.kind,
                content: output.text,
                attachments: interpreted.attachments,
                reasoningContent: reasoningTrimmed.flatMap { $0.isEmpty ? nil : $0 },
                reasoningDurationMs: output.reasoningDurationMs,
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
            let latestHistory = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
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
        memberID: Int?,
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
            if let memberID, active.memberID != memberID {
                let title = String(firstUserInput.prefix(18))
                let created = await repository.createThread(
                    memberID: memberID,
                    title: title.isEmpty ? promptLocalizer.newThreadTitle() : title
                )
                await repository.setActiveThread(id: created.id)
                return created
            }
            return active
        }

        let title = String(firstUserInput.prefix(18))
        let created = await repository.createThread(
            memberID: memberID,
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
}
