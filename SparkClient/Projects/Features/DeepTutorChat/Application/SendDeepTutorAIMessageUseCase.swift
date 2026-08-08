import Foundation

struct SendDeepTutorAIMessageUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository
    let adapter: DeepTutorAIRuntimeAdapter
    let turnCoordinator: DeepTutorTurnCoordinator
    let eventBus: DeepTutorTurnEventBus
    let logger: Logger

    func callAsFunction(
        conversationID: UUID,
        text: String,
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        boundMemberID: Int? = nil,
        requestedCanonicalTools: [String]? = nil,
        attachments: [DeepTutorAttachment] = [],
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        let conversation = await repository.loadConversation(id: conversationID)
        let plan = try await turnCoordinator.prepareSend(
            conversationID: conversationID,
            text: text,
            capability: capability,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            visibleHistory: visibleHistory,
            boundMemberID: boundMemberID,
            requestedCanonicalTools: requestedCanonicalTools,
            attachments: attachments
        )
        return try await execute(
            plan: plan,
            session: session,
            onStreamingUpdate: onStreamingUpdate
        )
    }

    func execute(
        plan: DeepTutorTurnPlan,
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        await eventBus.beginTurn(plan.turnID)
        do {
            let result = try await executeTurn(
                plan: plan,
                session: session,
                onStreamingUpdate: onStreamingUpdate
            )
            await eventBus.endTurn()
            return result
        } catch {
            await eventBus.endTurn()
            throw error
        }
    }

    func retryAssistant(
        conversationID: UUID,
        assistantMessageID: UUID,
        userMessageID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> DeepTutorMessage {
        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard let userMessage = messages.first(where: { $0.id == userMessageID && $0.role == .user }) else {
            throw DeepTutorChatError.messageNotFound
        }
        let conversation = await repository.loadConversation(id: conversationID)
        let plan = try await turnCoordinator.prepareRetry(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            userMessageID: userMessageID,
            capability: capability,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            visibleHistory: visibleHistory,
            userMessage: userMessage,
            boundMemberID: conversation?.memberID
        )
        let result = try await execute(
            plan: plan,
            session: session,
            onStreamingUpdate: onStreamingUpdate
        )
        return result.assistant
    }

    func regenerateAssistant(
        conversationID: UUID,
        assistantMessageID: UUID,
        userMessageID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard let userMessage = messages.first(where: { $0.id == userMessageID && $0.role == .user }) else {
            throw DeepTutorChatError.messageNotFound
        }
        let conversation = await repository.loadConversation(id: conversationID)
        let plan = try await turnCoordinator.prepareRegenerate(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            userMessageID: userMessageID,
            capability: capability,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            visibleHistory: visibleHistory,
            userMessage: userMessage,
            boundMemberID: conversation?.memberID
        )
        return try await execute(
            plan: plan,
            session: session,
            onStreamingUpdate: onStreamingUpdate
        )
    }

    func resolveAskUser(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer]
    ) async throws -> DeepTutorMessage {
        try await submitAskUser(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: toolCallID,
            answers: answers,
            capability: .chat,
            conversationTitle: DeepTutorSessionTitle.defaultSentinel,
            settings: .default,
            visibleHistory: await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil),
            session: DeepTutorGenerationSession(),
            onStreamingUpdate: nil
        )
    }

    func submitAskUser(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer],
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> DeepTutorMessage {
        let start = Date()
        let phaseBefore = "ready"
        DeepTutorChatLog.askUserSubmitStarted(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: toolCallID,
            answerCount: answers.count,
            phaseBefore: phaseBefore
        )

        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard var assistant = messages.first(where: { $0.id == assistantMessageID }) else {
            throw DeepTutorChatError.messageNotFound
        }
        guard let precedingUser = messages
            .filter({ $0.role == .user && $0.createdAt <= assistant.createdAt })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first else {
            throw DeepTutorChatError.messageNotFound
        }

        guard let canonicalToolCallID = DeepTutorAskUserToolCallIDMatcher.canonicalToolCallID(
            in: assistant,
            submittedToolCallID: toolCallID
        ) else {
            throw DeepTutorChatError.messageNotFound
        }

        logger.info(
            "DeepTutor 追问已恢复（DeepTutor inline），toolCall=\(canonicalToolCallID), answers=\(answers.count)",
            module: DeepTutorChatLog.module
        )

        var events = assistant.events
        events.append(.askUserResolved(toolCallID: canonicalToolCallID, answers: answers))
        assistant = assistant.replacing(events: events, status: .streaming)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
        await eventBus.publish(.askUserResolved(toolCallID: canonicalToolCallID, answers: answers))
        await onStreamingUpdate?(assistant)
        DeepTutorChatLog.askUserSubmitResolvedLocal(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: canonicalToolCallID,
            answerCount: answers.count
        )

        guard let resumeContext = DeepTutorAskUserResumeBuilder.buildContext(
            assistant: assistant,
            precedingUser: precedingUser,
            toolCallID: canonicalToolCallID,
            answers: answers
        ) else {
            throw DeepTutorChatError.messageNotFound
        }

        await session.bindAssistantMessageID(assistantMessageID)
        DeepTutorChatLog.askUserSubmitResumeStarted(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: canonicalToolCallID,
            resumeMode: "sameAssistantMessage"
        )

        let conversation = await repository.loadConversation(id: conversationID)

        let streamResult = try await adapter.resumeStream(
            DeepTutorAIRuntimeAdapter.ResumeStreamRequest(
                conversationID: conversationID,
                capability: capability,
                conversationTitle: conversationTitle,
                conversation: conversation,
                settings: settings,
                visibleHistory: visibleHistory.filter { $0.id != assistantMessageID },
                assistantMessage: assistant,
                resumeContext: resumeContext,
                requestSnapshot: precedingUser.requestSnapshot,
                priorToolSnapshot: precedingUser.requestSnapshot?.toolSnapshot,
                session: session,
                onAssistantUpdate: { [repository] updated in
                    await onStreamingUpdate?(updated)
                    let shouldPersist = await session.shouldFlushDatabase(force: updated.status == .ready)
                    if shouldPersist {
                        _ = try? await repository.upsertMessage(updated)
                        await session.markDatabaseFlushed()
                    }
                }
            )
        )

        var finalAssistant = streamResult.assistantMessage.replacing(status: .ready)
        finalAssistant = finalizeAssistantMessage(finalAssistant)
        _ = try await repository.upsertMessage(finalAssistant)
        await onStreamingUpdate?(finalAssistant)

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        DeepTutorChatLog.askUserSubmitResumeCompleted(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: canonicalToolCallID,
            phaseAfter: "ready",
            durationMs: durationMs
        )
        return finalAssistant
    }

    func submitMemberSelection(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        memberID: Int,
        memberName: String,
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> DeepTutorMessage {
        let start = Date()
        let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
        guard var assistant = messages.first(where: { $0.id == assistantMessageID }) else {
            throw DeepTutorChatError.messageNotFound
        }
        guard let precedingUser = messages
            .filter({ $0.role == .user && $0.createdAt <= assistant.createdAt })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first else {
            throw DeepTutorChatError.messageNotFound
        }

        let canonicalToolCallID = DeepTutorMemberSelectionResumeBuilder.canonicalToolCallID(
            in: assistant,
            submittedToolCallID: toolCallID
        )
        guard canonicalToolCallID.isEmpty == false else {
            throw DeepTutorChatError.messageNotFound
        }

        logger.info(
            "DeepTutor 成员选择已恢复（DeepTutor inline），toolCall=\(canonicalToolCallID), submittedToolCall=\(toolCallID), memberID=\(memberID)",
            module: DeepTutorChatLog.module
        )

        var events = assistant.events
        events.append(.memberSelectionResolved(toolCallID: canonicalToolCallID, memberID: memberID, memberName: memberName))
        assistant = assistant.replacing(events: events, status: .streaming)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
        await eventBus.publish(.memberSelectionResolved(toolCallID: canonicalToolCallID, memberID: memberID, memberName: memberName))
        await onStreamingUpdate?(assistant)

        try await repository.updateConversationMemberBinding(conversationID: conversationID, memberID: memberID)
        DeepTutorChatLog.memberSelectionConversationBound(
            conversationID: conversationID,
            oldMemberID: nil,
            newMemberID: memberID,
            persisted: true
        )

        guard let resumeContext = DeepTutorMemberSelectionResumeBuilder.buildContext(
            assistant: assistant,
            precedingUser: precedingUser,
            toolCallID: canonicalToolCallID,
            memberID: memberID,
            memberName: memberName
        ) else {
            throw DeepTutorChatError.messageNotFound
        }

        await session.bindAssistantMessageID(assistantMessageID)

        let conversation = await repository.loadConversation(id: conversationID)

        let streamResult = try await adapter.resumeMemberSelectionStream(
            DeepTutorAIRuntimeAdapter.MemberSelectionResumeStreamRequest(
                conversationID: conversationID,
                capability: capability,
                conversationTitle: conversationTitle,
                conversation: conversation,
                settings: settings,
                visibleHistory: visibleHistory.filter { $0.id != assistantMessageID },
                assistantMessage: assistant,
                resumeContext: resumeContext,
                requestSnapshot: precedingUser.requestSnapshot,
                priorToolSnapshot: precedingUser.requestSnapshot?.toolSnapshot,
                session: session,
                onAssistantUpdate: { [repository] updated in
                    await onStreamingUpdate?(updated)
                    let shouldPersist = await session.shouldFlushDatabase(force: updated.status == .ready)
                    if shouldPersist {
                        _ = try? await repository.upsertMessage(updated)
                        await session.markDatabaseFlushed()
                    }
                }
            )
        )

        var finalAssistant = streamResult.assistantMessage.replacing(status: .ready)
        finalAssistant = finalizeAssistantMessage(finalAssistant)
        _ = try await repository.upsertMessage(finalAssistant)
        await onStreamingUpdate?(finalAssistant)

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        DeepTutorChatLog.memberSelectionContinuationResumed(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            toolCallID: canonicalToolCallID,
            memberID: memberID,
            durationMs: durationMs
        )
        return finalAssistant
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

    // MARK: - Private

	    private func executeTurn(
        plan: DeepTutorTurnPlan,
        session: DeepTutorGenerationSession,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)?
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        let conversationID = plan.conversationID
        let capability = plan.capability
        let settings = plan.settings
        let visibleHistory = plan.visibleHistory
        let requestSnapshot = plan.snapshot
        let boundMemberID = plan.boundMemberID

        let userMessage: DeepTutorMessage
        let userInput: String
        let historyForModel: [DeepTutorMessage]
        let assistantID: UUID

        switch plan.intent {
        case .send(let userText):
            let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            let persistedAttachments = requestSnapshot.attachments
            guard trimmed.isEmpty == false || persistedAttachments.isEmpty == false else {
                throw DeepTutorChatError.emptyInput
            }
            userInput = trimmed
            let now = Date()
            userMessage = DeepTutorMessageReducer.applyBlocks(
                to: DeepTutorMessage(
                    conversationID: conversationID,
                    role: .user,
                    content: trimmed,
                    capability: capability,
                    attachments: persistedAttachments,
                    requestSnapshot: requestSnapshot,
                    status: .ready,
                    createdAt: now,
                    updatedAt: now
                )
            )
            _ = try await repository.upsertMessage(userMessage)
            await onStreamingUpdate?(userMessage)
            DeepTutorAttachmentDiagnostics.snapshotSaved(
                messageID: userMessage.id,
                attachmentCount: userMessage.attachments.count
            )
            if DeepTutorDebugFlags.verboseChatStreamLogs {
                logger.info(
                    "用户消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(userMessage.id)), status=\(DeepTutorChatLog.statusLabel(userMessage.status)), content=\(DeepTutorChatLog.contentSnippet(trimmed))",
                    module: DeepTutorChatLog.module
                )
            }
            historyForModel = visibleHistory
            assistantID = UUID()
        case .retryAssistant(let assistantMessageID, let userMessageID):
            let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
            guard let existingUser = messages.first(where: { $0.id == userMessageID && $0.role == .user }) else {
                throw DeepTutorChatError.messageNotFound
            }
            guard messages.contains(where: { $0.id == assistantMessageID && $0.role == .assistant }) else {
                throw DeepTutorChatError.messageNotFound
            }
            userMessage = existingUser
            userInput = existingUser.content
            historyForModel = visibleHistory.filter { $0.id != assistantMessageID }
            assistantID = assistantMessageID
            var failedAssistant = messages.first(where: { $0.id == assistantMessageID })!
            failedAssistant = failedAssistant.replacing(content: "", events: [], status: .streaming)
            failedAssistant = DeepTutorMessageReducer.applyBlocks(to: failedAssistant)
            _ = try await repository.upsertMessage(failedAssistant)
            await onStreamingUpdate?(failedAssistant)
        case .regenerate(let assistantMessageID, let userMessageID):
            let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
            guard let existingUser = messages.first(where: { $0.id == userMessageID && $0.role == .user }) else {
                throw DeepTutorChatError.messageNotFound
            }
            userMessage = existingUser
            userInput = existingUser.content
            historyForModel = visibleHistory.filter { $0.id != assistantMessageID }
            assistantID = UUID()
        }

        let loadedConversation: DeepTutorConversation?
        if let conversation = plan.conversation {
            loadedConversation = conversation
        } else {
            loadedConversation = await repository.loadConversation(id: conversationID)
        }

        await session.bindAssistantMessageID(assistantID)

        var assistant = DeepTutorMessageReducer.applyBlocks(
            to: DeepTutorMessage(
                id: assistantID,
                conversationID: conversationID,
                role: .assistant,
                content: "",
                capability: capability,
                status: .streaming,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        if case .send = plan.intent {
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            if DeepTutorDebugFlags.verboseChatStreamLogs {
                logger.info(
                    "助手消息落库（流式开始），conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status))",
                    module: DeepTutorChatLog.module
                )
            }
        } else if case .regenerate = plan.intent {
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            if DeepTutorDebugFlags.verboseChatStreamLogs {
                logger.info(
                    "助手消息落库（重新生成开始），conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status))",
                    module: DeepTutorChatLog.module
                )
            }
        }

	        do {
	            let streamResult = try await adapter.stream(
	                DeepTutorAIRuntimeAdapter.StreamRequest(
	                    conversationID: conversationID,
	                    userInput: userInput,
	                    capability: capability,
	                    conversationTitle: plan.conversationTitle,
	                    conversation: loadedConversation,
	                    settings: settings,
	                    visibleHistory: historyForModel,
	                    currentUserMessage: userMessage,
	                    assistantMessageID: assistantID,
	                    boundMemberID: boundMemberID,
	                    requestSnapshot: requestSnapshot,
	                    modelResolutionMode: plan.modelResolutionMode,
	                    session: session,
	                    onAssistantUpdate: { [repository, logger] updated in
	                        await onStreamingUpdate?(updated)
	                        let forcePersist = Self.shouldForcePersist(updated)
	                        let shouldPersist = await session.shouldFlushDatabase(force: forcePersist)
	                        if shouldPersist {
	                            _ = try? await repository.upsertMessage(updated)
                            await session.markDatabaseFlushed()
                            if forcePersist, DeepTutorDebugFlags.verboseChatRefreshLogs {
                                logger.info(
                                    "deeptutor.ask_user.persisted conversation=\(DeepTutorChatLog.shortID(updated.conversationID)) message=\(DeepTutorChatLog.shortID(updated.id)) askUserBlocks=\(updated.blocks.filter { $0.kind == .askUser }.count)",
                                    module: DeepTutorChatLog.module
	                                )
	                            }
	                        }
	                    }
	                )
	            )
            assistant = streamResult.assistantMessage.replacing(status: .ready)
            assistant = finalizeAssistantMessage(assistant)
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            if DeepTutorDebugFlags.verboseChatStreamLogs {
                logger.info(
                    "助手消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status)), content=\(DeepTutorChatLog.contentSnippet(assistant.content))",
                    module: DeepTutorChatLog.module
                )
            }
            return (userMessage, assistant)
        } catch {
            if let reloaded = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
                .first(where: { $0.id == assistantID }) {
                assistant = reloaded
            }
            let cancelled = await session.isCancelled
            if cancelled == false,
               case AIRuntimeError.emptyOutput = error,
               DeepTutorContentRouter.shouldAcceptEmptyOutput(assistant, finishReason: nil) {
                assistant = assistant.replacing(status: .ready)
                assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
                _ = try await repository.upsertMessage(assistant)
                await onStreamingUpdate?(assistant)
                logger.info(
                    "DeepTutor 空输出已按 pending ask_user 处理，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id))",
                    module: DeepTutorChatLog.module
                )
                return (userMessage, assistant)
            }
            let message = DeepTutorRuntimeRequestBuilder.userFacingConfigError(error)
            var events = assistant.events
            if cancelled {
                logger.info(
                    "DeepTutor AI 流式已取消，conversation=\(DeepTutorChatLog.shortID(conversationID))",
                    module: DeepTutorChatLog.module
                )
                assistant = assistant.replacing(
                    content: assistant.content,
                    events: events,
                    status: assistant.content.isEmpty ? .failed : .ready
                )
            } else {
                events.append(.error(message: message, turnTerminal: true))
                assistant = assistant.replacing(
                    content: assistant.content,
                    events: events,
                    status: .failed
                )
            }
            assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            if cancelled == false {
                throw error
            }
            return (userMessage, assistant)
        }
    }

    nonisolated private static func shouldForcePersist(_ message: DeepTutorMessage) -> Bool {
        message.blocks.contains { block in
            switch block.payload {
            case let .askUser(payload):
                return payload.isResolved == false
            case let .memberSelection(payload):
                return payload.isResolved == false
            default:
                return false
            }
        }
    }

    nonisolated private func finalizeAssistantMessage(_ assistant: DeepTutorMessage) -> DeepTutorMessage {
        let parsed = DeepTutorQuizContentParser.apply(to: assistant)
        return DeepTutorMessageReducer.applyBlocks(to: parsed)
    }
}
