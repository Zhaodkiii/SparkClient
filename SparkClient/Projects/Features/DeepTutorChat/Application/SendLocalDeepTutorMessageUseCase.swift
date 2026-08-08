import Foundation

struct SendLocalDeepTutorMessageUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository
    let logger: Logger

    init(repository: any DeepTutorLocalChatRepository, logger: Logger = ConsoleLogger()) {
        self.repository = repository
        self.logger = logger
    }

    func callAsFunction(
        conversationID: UUID,
        text: String,
        capability: DeepTutorCapability,
        requestSnapshot: DeepTutorRequestSnapshot? = nil,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DeepTutorChatError.emptyInput
        }

        let start = Date()

        let now = Date()
        let userMessage = DeepTutorMessageReducer.applyBlocks(
            to: DeepTutorMessage(
                conversationID: conversationID,
                role: .user,
                content: trimmed,
                capability: capability,
                requestSnapshot: requestSnapshot,
                status: .ready,
                createdAt: now,
                updatedAt: now
            )
        )
        _ = try await repository.upsertMessage(userMessage)
        await onStreamingUpdate?(userMessage)
        if DeepTutorDebugFlags.verboseChatStreamLogs {
            logger.info(
                "用户消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(userMessage.id)), status=\(DeepTutorChatLog.statusLabel(userMessage.status)), content=\(DeepTutorChatLog.contentSnippet(trimmed))",
                module: DeepTutorChatLog.module
            )
        }

        var assistant = DeepTutorMessageReducer.applyBlocks(
            to: DeepTutorMessage(
                conversationID: conversationID,
                role: .assistant,
                content: "",
                capability: capability,
                status: .streaming,
                createdAt: now.addingTimeInterval(0.01),
                updatedAt: now.addingTimeInterval(0.01)
            )
        )
        _ = try await repository.upsertMessage(assistant)
        await onStreamingUpdate?(assistant)
        if DeepTutorDebugFlags.verboseChatStreamLogs {
            logger.info(
                "助手消息落库（流式开始），conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status))",
                module: DeepTutorChatLog.module
            )
        }

        let simulation = DeepTutorLocalReplySimulator.simulate(
            userText: trimmed,
            capability: capability,
            assistantMessageID: assistant.id,
            conversationID: conversationID
        )

        for step in simulation.steps {
            try await Task.sleep(nanoseconds: step.delayNanoseconds)
            assistant = step.apply(assistant)
            assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
        }

        assistant = assistant.replacing(status: .ready)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
        await onStreamingUpdate?(assistant)

        let cost = Date().timeIntervalSince(start)
        if DeepTutorDebugFlags.verboseChatStreamLogs {
            logger.info(
                "助手消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status)), content=\(DeepTutorChatLog.contentSnippet(assistant.content)), cost=\(DeepTutorChatLog.format(cost))s",
                module: DeepTutorChatLog.module
            )
        }
        return (userMessage, assistant)
    }

    func resolveAskUser(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer]
    ) async throws -> DeepTutorMessage {
        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard var assistant = messages.first(where: { $0.id == assistantMessageID }) else {
            throw DeepTutorChatError.messageNotFound
        }
        var events = assistant.events
        events.append(.askUserResolved(toolCallID: toolCallID, answers: answers))
        events.append(.contentDelta(text: "\n\nThanks — continuing with your answer.", callID: nil, round: nil))
        assistant = assistant.replacing(
            content: assistant.content + "\n\nThanks — continuing with your answer.",
            events: events,
            status: .ready
        )
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
        return assistant
    }

    func editUserMessage(
        conversationID: UUID,
        messageID: UUID,
        newText: String
    ) async throws -> DeepTutorMessage {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DeepTutorChatError.emptyInput
        }
        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard let original = messages.first(where: { $0.id == messageID && $0.role == .user }) else {
            throw DeepTutorChatError.messageNotFound
        }
        let now = Date()
        let branchMessage = DeepTutorMessageReducer.applyBlocks(
            to: DeepTutorMessage(
                conversationID: conversationID,
                role: .user,
                content: trimmed,
                capability: original.capability,
                attachments: original.attachments,
                requestSnapshot: original.requestSnapshot,
                parentMessageID: original.parentMessageID ?? original.id,
                status: .ready,
                createdAt: now,
                updatedAt: now
            )
        )
        _ = try await repository.upsertMessage(branchMessage)
        return branchMessage
    }
}
