import Foundation

struct SendDeepTutorAIMessageUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository
    let adapter: DeepTutorAIRuntimeAdapter
    let toolInteractionCoordinator: ToolInteractionCoordinator
    let logger: Logger

    enum Mode: Sendable {
        case send(userText: String)
        case retryAssistant(assistantMessageID: UUID, userMessageID: UUID)
        case regenerate(assistantMessageID: UUID, userMessageID: UUID)
    }

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
        requestSnapshot: DeepTutorRequestSnapshot? = nil,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)? = nil
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        let resolvedSnapshot = requestSnapshot ?? Self.buildRequestSnapshot(
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            userInput: text,
            requestedCanonicalTools: requestedCanonicalTools,
            boundMemberID: boundMemberID
        )
        return try await execute(
            mode: .send(userText: text),
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            settings: settings,
            visibleHistory: visibleHistory,
            session: session,
            boundMemberID: boundMemberID,
            requestSnapshot: resolvedSnapshot,
            onStreamingUpdate: onStreamingUpdate
        )
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
        let result = try await execute(
            mode: .retryAssistant(assistantMessageID: assistantMessageID, userMessageID: userMessageID),
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            settings: settings,
            visibleHistory: visibleHistory,
            session: session,
            requestSnapshot: nil,
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
        try await execute(
            mode: .regenerate(assistantMessageID: assistantMessageID, userMessageID: userMessageID),
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            settings: settings,
            visibleHistory: visibleHistory,
            session: session,
            requestSnapshot: nil,
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

        if let active = await MainActor.run(body: { toolInteractionCoordinator.activePresentation }),
           case .question = active.snapshot {
            let askPayload = assistant.events.compactMap { event -> DeepTutorAskUserPayload? in
                if case let .askUser(payload, id) = event, id == canonicalToolCallID { return payload }
                return nil
            }.first
            let mapped = askPayload.map {
                DeepTutorAskUserAnswerMapper.toolQuestionAnswer(deeptutorAnswers: answers, payload: $0)
            } ?? ToolQuestionAnswer(responses: answers.map {
                ToolQuestionResponse(questionID: $0.questionID, selectedOptionIDs: [], otherText: $0.text)
            })
            await MainActor.run {
                toolInteractionCoordinator.completeQuestion(id: active.id, answer: mapped)
            }
            logger.info(
                "DeepTutor 追问已恢复（sheet），prompt=\(DeepTutorChatLog.shortID(active.id)), toolCall=\(canonicalToolCallID)",
                module: DeepTutorChatLog.module
            )
        } else {
            logger.info(
                "DeepTutor 追问已恢复（inline），toolCall=\(canonicalToolCallID), answers=\(answers.count)",
                module: DeepTutorChatLog.module
            )
        }

        var events = assistant.events
        events.append(.askUserResolved(toolCallID: canonicalToolCallID, answers: answers))
        assistant = assistant.replacing(events: events, status: .streaming)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
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

        let streamResult = try await adapter.resumeStream(
            DeepTutorAIRuntimeAdapter.ResumeStreamRequest(
                conversationID: conversationID,
                capability: capability,
                conversationTitle: conversationTitle,
                settings: settings,
                visibleHistory: visibleHistory.filter { $0.id != assistantMessageID },
                assistantMessage: assistant,
                resumeContext: resumeContext,
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

        if let active = await MainActor.run(body: { toolInteractionCoordinator.activePresentation }),
           case .member = active.snapshot {
            await MainActor.run {
                toolInteractionCoordinator.completeMemberSelection(id: active.id, memberID: memberID)
            }
            logger.info(
                "DeepTutor 成员选择已恢复（sheet fallback），prompt=\(DeepTutorChatLog.shortID(active.id)), toolCall=\(toolCallID)",
                module: DeepTutorChatLog.module
            )
        } else {
            logger.info(
                "DeepTutor 成员选择已恢复（inline），toolCall=\(toolCallID), memberID=\(memberID)",
                module: DeepTutorChatLog.module
            )
        }

        var events = assistant.events
        events.append(.memberSelectionResolved(toolCallID: toolCallID, memberID: memberID, memberName: memberName))
        assistant = assistant.replacing(events: events, status: .streaming)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        _ = try await repository.upsertMessage(assistant)
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
            toolCallID: toolCallID,
            memberID: memberID,
            memberName: memberName
        ) else {
            throw DeepTutorChatError.messageNotFound
        }

        await session.bindAssistantMessageID(assistantMessageID)

        let streamResult = try await adapter.resumeMemberSelectionStream(
            DeepTutorAIRuntimeAdapter.MemberSelectionResumeStreamRequest(
                conversationID: conversationID,
                capability: capability,
                conversationTitle: conversationTitle,
                settings: settings,
                visibleHistory: visibleHistory.filter { $0.id != assistantMessageID },
                assistantMessage: assistant,
                resumeContext: resumeContext,
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
            toolCallID: toolCallID,
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

	    private func execute(
        mode: Mode,
        conversationID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        session: DeepTutorGenerationSession,
        boundMemberID: Int? = nil,
        requestSnapshot: DeepTutorRequestSnapshot?,
        onStreamingUpdate: (@Sendable (DeepTutorMessage) async -> Void)?
    ) async throws -> (user: DeepTutorMessage, assistant: DeepTutorMessage) {
        DeepTutorChatLog.capabilitySnapshot(
            conversationID: conversationID,
            requestSnapshotCapability: capability.rawValue,
            messageCapability: capability.rawValue
        )

        let userMessage: DeepTutorMessage
        let userInput: String
        let historyForModel: [DeepTutorMessage]
        let assistantID: UUID
        var replaySnapshot: DeepTutorRequestSnapshot?

        switch mode {
        case .send(let userText):
            let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { throw DeepTutorChatError.emptyInput }
            userInput = trimmed
            let now = Date()
            userMessage = DeepTutorMessageReducer.applyBlocks(
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
            logger.info(
                "用户消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(userMessage.id)), status=\(DeepTutorChatLog.statusLabel(userMessage.status)), content=\(DeepTutorChatLog.contentSnippet(trimmed))",
                module: DeepTutorChatLog.module
            )
            historyForModel = visibleHistory
            assistantID = UUID()
            replaySnapshot = requestSnapshot
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
            replaySnapshot = existingUser.requestSnapshot
        case .regenerate(let assistantMessageID, let userMessageID):
            let messages = await repository.loadMessages(conversationID: conversationID, limit: nil, before: nil)
            guard let existingUser = messages.first(where: { $0.id == userMessageID && $0.role == .user }) else {
                throw DeepTutorChatError.messageNotFound
            }
            userMessage = existingUser
            userInput = existingUser.content
            historyForModel = visibleHistory.filter { $0.id != assistantMessageID }
            assistantID = UUID()
            replaySnapshot = existingUser.requestSnapshot
        }

        let effectiveSnapshot = replaySnapshot ?? requestSnapshot

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
        if case .send = mode {
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            logger.info(
                "助手消息落库（流式开始），conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status))",
                module: DeepTutorChatLog.module
            )
        } else if case .regenerate = mode {
            _ = try await repository.upsertMessage(assistant)
            await onStreamingUpdate?(assistant)
            logger.info(
                "助手消息落库（重新生成开始），conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status))",
                module: DeepTutorChatLog.module
            )
        }

	        do {
	            let streamResult = try await adapter.stream(
	                DeepTutorAIRuntimeAdapter.StreamRequest(
	                    conversationID: conversationID,
	                    userInput: userInput,
	                    capability: capability,
	                    conversationTitle: conversationTitle,
	                    settings: settings,
	                    visibleHistory: historyForModel,
	                    assistantMessageID: assistantID,
	                    boundMemberID: boundMemberID,
	                    requestSnapshot: effectiveSnapshot,
	                    session: session,
	                    onAssistantUpdate: { [repository, logger] updated in
	                        await onStreamingUpdate?(updated)
	                        let forcePersist = Self.shouldForcePersist(updated)
	                        let shouldPersist = await session.shouldFlushDatabase(force: forcePersist)
	                        if shouldPersist {
	                            _ = try? await repository.upsertMessage(updated)
	                            await session.markDatabaseFlushed()
	                            if forcePersist {
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
            logger.info(
                "助手消息落库成功，conversation=\(DeepTutorChatLog.shortID(conversationID)), messageID=\(DeepTutorChatLog.shortID(assistant.id)), status=\(DeepTutorChatLog.statusLabel(assistant.status)), content=\(DeepTutorChatLog.contentSnippet(assistant.content))",
                module: DeepTutorChatLog.module
            )
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

    nonisolated static func buildRequestSnapshot(
        conversationID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        userInput: String,
        requestedCanonicalTools: [String]?,
        boundMemberID: Int?
    ) -> DeepTutorRequestSnapshot {
        var mountContext = DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: conversationID,
            conversationTitle: conversationTitle
        )
        mountContext.hasSelectedMember = boundMemberID != nil && (boundMemberID ?? 0) > 0
        if let requestedCanonicalTools {
            mountContext.snapshotRequestedTools = requestedCanonicalTools
        }
        if capability == .deepQuestion {
            mountContext.toolPhase = .explore
        }
        let policy = DeepTutorToolPolicyResolver.resolve(mountContext)
        return DeepTutorToolPolicyResolver.makePerTurnSnapshot(for: mountContext, policy: policy)
    }
}
