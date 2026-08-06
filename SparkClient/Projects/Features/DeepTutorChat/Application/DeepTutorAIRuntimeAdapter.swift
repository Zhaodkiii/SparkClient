import Foundation

struct DeepTutorAIRuntimeAdapter: Sendable {
    let orchestrator: ChatOrchestrator
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    struct StreamRequest: Sendable {
        let conversationID: UUID
        let userInput: String
        let capability: DeepTutorCapability
        let conversationTitle: String
        let settings: DeepTutorConversationGenerationSettings
        let visibleHistory: [DeepTutorMessage]
        let assistantMessageID: UUID
        let boundMemberID: Int?
        let requestSnapshot: DeepTutorRequestSnapshot?
        let session: DeepTutorGenerationSession
        let onAssistantUpdate: @Sendable (DeepTutorMessage) async -> Void
    }

    struct StreamResult: Sendable {
        let output: ChatOrchestratorOutput
        let assistantMessage: DeepTutorMessage
        let resolvedModel: String?
        let resolvedProvider: String?
        let resolvedSource: String?
        let resolvedEndpoint: String?
    }

    func stream(_ request: StreamRequest) async throws -> StreamResult {
        let conversationShortID = DeepTutorChatLog.shortID(request.conversationID)
        logger.info(
            "DeepTutor AI 推理开始，conversation=\(conversationShortID), capability=\(request.capability.rawValue), userContent=\(DeepTutorChatLog.contentSnippet(request.userInput))",
            module: DeepTutorChatLog.module
        )

        let preliminaryPreferredModel = request.settings.currentModelName

        let resolvedConfig: AIResolvedConfig
        do {
            resolvedConfig = try await aiConfigCenter.resolve(
                for: .chat,
                preferredModelName: preliminaryPreferredModel
            )
            logger.debug(
                "DeepTutor AI 配置已解析，conversation=\(conversationShortID), model=\(resolvedConfig.model), source=\(resolvedConfig.source.rawValue)",
                module: DeepTutorChatLog.module
            )
        } catch {
            logger.error(
                "DeepTutor AI 配置解析失败，conversation=\(conversationShortID), error=\(error.localizedDescription)",
                module: DeepTutorChatLog.module
            )
            throw error
        }

        let bundles = try? await aiConfigCenter.effectiveScenarioBundles()
        let modelReasoning = bundles?.chatReasoningContext(selectedModelName: preliminaryPreferredModel) ?? .unknown
        let modelSupportsToolCalling = Self.modelSupportsToolCalling(
            modelName: resolvedConfig.model,
            bundles: bundles
        )

        var mountContext = DeepTutorToolMountContext.default(
            capability: request.capability,
            userInput: request.userInput,
            conversationID: request.conversationID,
            conversationTitle: request.conversationTitle
        )
        mountContext.modelSupportsToolCalling = modelSupportsToolCalling
        mountContext.hasSelectedMember = request.boundMemberID != nil && (request.boundMemberID ?? 0) > 0
        mountContext.snapshotRequestedTools = request.requestSnapshot?.enabledTools
            ?? request.requestSnapshot?.toolSnapshot?.requestedCanonicalTools
        if request.capability == .deepQuestion {
            mountContext.toolPhase = .explore
        }
        DeepTutorChatLog.toolPolicyInput(
            conversationID: request.conversationID,
            assistantMessageID: request.assistantMessageID,
            capability: request.capability,
            selectedTools: mountContext.snapshotRequestedTools ?? [],
            snapshotTools: request.requestSnapshot?.enabledTools ?? []
        )

        let built = DeepTutorRuntimeRequestBuilder.build(
            userInput: request.userInput,
            capability: request.capability,
            conversationID: request.conversationID,
            conversationTitle: request.conversationTitle,
            settings: request.settings,
            visibleHistory: request.visibleHistory,
            preferredModelName: preliminaryPreferredModel,
            mountContext: mountContext
        )

        DeepTutorChatLog.toolPolicyResolved(
            conversationID: request.conversationID,
            assistantMessageID: request.assistantMessageID,
            capability: request.capability,
            inputLength: request.userInput.count,
            policy: built.toolPolicy,
            modelSupportsToolCalling: modelSupportsToolCalling
        )

        let outboundSchemaNames = DeepTutorToolPolicyResolver.effectiveToolSchemaNames(inference: built.inference)
        let toolChoiceLabel = built.inference.useTools && outboundSchemaNames.isEmpty == false ? "auto" : "none"
        DeepTutorChatLog.toolSchemaOutbound(
            conversationID: request.conversationID,
            assistantMessageID: request.assistantMessageID,
            toolChoice: toolChoiceLabel,
            schemaNames: outboundSchemaNames,
            reason: built.toolPolicy.policyReason
        )

        let accumulator = DeepTutorAIRuntimeStreamAccumulator(
            assistant: DeepTutorMessage(
                id: request.assistantMessageID,
                conversationID: request.conversationID,
                role: .assistant,
                content: "",
                capability: request.capability,
                status: .streaming
            )
        )

        let streamStart = Date()
        let cancellationToken = await request.session.cancellationToken
        let toolCallLogger = DeepTutorToolCallLogTracker()
        let flushTracker = DeepTutorPartialFlushTracker()
        let output: ChatOrchestratorOutput
        do {
            output = try await orchestrator.generateReply(
                userInput: request.userInput,
                history: built.history,
                memberContextSummary: "",
                memberID: request.boundMemberID,
                threadID: request.conversationID,
                assistantMessageClientID: request.assistantMessageID,
                inference: built.inference,
                modelReasoning: modelReasoning,
                systemPrompt: built.systemPrompt,
                preferredModelName: built.preferredModelName,
                temperature: built.temperature ?? resolvedConfig.temperature,
                topP: built.topP,
                maxTokens: resolvedConfig.maxTokens,
                maxMessages: built.maxMessages,
                cancellationToken: cancellationToken,
                preferInlineAskUser: true,
                preferInlineMemberSelection: true,
                onPartial: { partial in
                    guard partial.answer.isEmpty == false
                        || partial.reasoning?.isEmpty == false
                        || partial.toolName != nil else {
                        return
                    }
                    let mapped = await accumulator.apply(partial: partial)
                    let updated = mapped.message
                    let hasNewEvents = mapped.events.isEmpty == false
                    let hasAskUser = Self.containsAskUserEvent(mapped.events)
                    let hasMemberSelection = Self.containsMemberSelectionEvent(mapped.events)
                    let shouldForceFlush = hasAskUser || hasMemberSelection || Self.containsStructuralEvent(mapped.events)
                    let blockSummary = Self.blockSummary(updated.blocks)
                    let shouldUpdateUI = await flushTracker.shouldFlush(
                        signature: [
                            partial.toolCallID ?? "-",
                            partial.toolArguments ?? "-",
                            Self.eventSummary(mapped.events),
                            blockSummary,
                        ].joined(separator: "|"),
                        force: shouldForceFlush
                    )
                    let shouldLogPartial = shouldUpdateUI && hasNewEvents
                    if shouldLogPartial {
                        logger.debug(
                            "deeptutor.stream.partial.mapped conversation=\(conversationShortID) assistant=\(DeepTutorChatLog.shortID(request.assistantMessageID)) tool=\(partial.toolName ?? "-") call=\(partial.toolCallID ?? "-") answerLen=\(partial.answer.count) reasoningLen=\(partial.reasoning?.count ?? 0) events=\(Self.eventSummary(mapped.events)) forceFlush=\(shouldForceFlush) blocks=\(blockSummary)",
                            module: DeepTutorChatLog.module
                        )
                    }
                    if let toolName = partial.toolName, let toolCallID = partial.toolCallID {
                        let argsLength = partial.toolArguments?.count
                            ?? partial.toolInvocationArguments?.values.joined().count
                            ?? 0
                        let logEvent = await toolCallLogger.record(
                            toolCallID: toolCallID,
                            toolInvocationArguments: partial.toolInvocationArguments,
                            toolContent: partial.toolContent,
                            streamStart: streamStart
                        )
                        if let logEvent {
                            switch logEvent {
                            case .received(let round):
                                DeepTutorChatLog.toolCallReceived(
                                    conversationID: request.conversationID,
                                    assistantMessageID: request.assistantMessageID,
                                    round: round,
                                    toolName: toolName,
                                    toolCallID: toolCallID,
                                    argumentsLength: argsLength,
                                    wasAllowedByPolicy: DeepTutorToolPolicyResolver.isToolAllowed(
                                        toolName,
                                        by: built.toolPolicy
                                    ),
                                    allowedToolCount: built.toolPolicy.allowedToolNames.count
                                )
                                if toolName == SparkToolName.askUserQuestion.rawValue {
                                    logger.info(
                                        "deeptutor.ask_user.policy_selected conversation=\(conversationShortID) call=\(toolCallID) reason=\(built.toolPolicy.policyReason)",
                                        module: DeepTutorChatLog.module
                                    )
                                }
                            case .completed(let round, let durationMs, let resultLength):
                                DeepTutorChatLog.toolCallCompleted(
                                    conversationID: request.conversationID,
                                    assistantMessageID: request.assistantMessageID,
                                    round: round,
                                    toolName: toolName,
                                    toolCallID: toolCallID,
                                    status: "success",
                                    durationMs: durationMs,
                                    resultLength: resultLength,
                                    sideEffectCount: 0,
                                    awaitingUserInput: Self.containsAskUserEvent(mapped.events)
                                )
                            }
                        }
                    }
                    let force = await request.session.shouldFlushUI(force: shouldForceFlush && shouldUpdateUI)
                    if force {
                        await request.onAssistantUpdate(updated)
                    }
                }
            )
        } catch {
            if case AIRuntimeError.emptyOutput = error {
                let interim = await accumulator.snapshot()
                if DeepTutorContentRouter.shouldAcceptEmptyOutput(interim, finishReason: nil) {
                    let reasoningLen = interim.events.compactMap { event -> Int? in
                        if case let .reasoningDelta(text, _, _) = event { return text.count }
                        return nil
                    }.reduce(0, +)
                    let toolCallCount = interim.events.filter {
                        if case .toolCallStarted = $0 { return true }
                        return false
                    }.count
                    let askUserPayloadCount = interim.events.filter {
                        if case .askUser = $0 { return true }
                        return false
                    }.count
                    let decision = DeepTutorContentRouter.classifyEmptyOutput(
                        message: interim,
                        finishReason: "awaiting_user_input",
                        textLen: interim.content.count,
                        reasoningLen: reasoningLen,
                        toolCallCount: toolCallCount,
                        askUserPayloadCount: askUserPayloadCount
                    )
                    DeepTutorChatLog.emptyOutputClassified(
                        conversationID: request.conversationID,
                        messageID: request.assistantMessageID,
                        finishReason: "awaiting_user_input",
                        textLen: interim.content.count,
                        reasoningLen: reasoningLen,
                        toolCallCount: toolCallCount,
                        askUserPayloadCount: askUserPayloadCount,
                        activePresentationSnapshot: "none",
                        decision: decision
                    )
                    let recoveredOutput = ChatOrchestratorOutput(
                        text: DeepTutorContentRouter.finalAnswerContent(from: interim),
                        reasoningText: nil,
                        reasoningDurationMs: nil,
                        finishReason: "awaiting_user_input",
                        kind: .text,
                        toolName: nil,
                        toolContent: nil,
                        blocks: []
                    )
                    let completionEvents = await accumulator.completionEvents(
                        output: recoveredOutput,
                        resolvedModel: resolvedConfig.model,
                        promptTokens: nil,
                        completionTokens: nil,
                        finishReason: recoveredOutput.finishReason
                    )
                    var assistant = await accumulator.applyCompletion(
                        events: completionEvents,
                        content: DeepTutorContentRouter.finalAnswerContent(from: interim)
                    )
                    assistant = assistant.replacing(status: .ready)
                    assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
                    await request.onAssistantUpdate(assistant)
                    let cost = Date().timeIntervalSince(streamStart)
                    logger.info(
                        "DeepTutor AI 空输出已恢复为 pending ask_user，conversation=\(conversationShortID), askUserBlocks=\(assistant.blocks.filter { $0.kind == .askUser }.count), cost=\(DeepTutorChatLog.format(cost))s",
                        module: DeepTutorChatLog.module
                    )
                    return StreamResult(
                        output: recoveredOutput,
                        assistantMessage: assistant,
                        resolvedModel: resolvedConfig.model,
                        resolvedProvider: resolvedConfig.source.rawValue,
                        resolvedSource: resolvedConfig.source.rawValue,
                        resolvedEndpoint: resolvedConfig.endpoint.absoluteString
                    )
                }
            }
            let cost = Date().timeIntervalSince(streamStart)
            if error is CancellationError {
                logger.info(
                    "DeepTutor AI 流式已中断，conversation=\(conversationShortID), cost=\(DeepTutorChatLog.format(cost))s",
                    module: DeepTutorChatLog.module
                )
            } else {
                logger.error(
                    "DeepTutor AI 流式失败，conversation=\(conversationShortID), cost=\(DeepTutorChatLog.format(cost))s, error=\(error.localizedDescription)",
                    module: DeepTutorChatLog.module
                )
            }
            throw error
        }

        let completionEvents = await accumulator.completionEvents(
            output: output,
            resolvedModel: resolvedConfig.model,
            promptTokens: nil,
            completionTokens: nil,
            finishReason: output.finishReason
        )
        logger.info(
            "deeptutor.stream.completion.mapped conversation=\(conversationShortID) assistant=\(DeepTutorChatLog.shortID(request.assistantMessageID)) finish=\(output.finishReason ?? "-") outputTool=\(output.toolName ?? "-") outputTextLen=\(output.text.count) events=\(Self.eventSummary(completionEvents))",
            module: DeepTutorChatLog.module
        )
        var assistant = await accumulator.applyCompletion(
            events: completionEvents,
            content: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        assistant = Self.salvageQuizPayloadAtCompletion(
            assistant: assistant,
            rawOutputText: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        let routedContent = DeepTutorContentRouter.finalAnswerContent(from: assistant)
        if routedContent != assistant.content {
            assistant = assistant.replacing(content: routedContent)
            assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        }
        if output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let reasoningLen = output.reasoningText?.count ?? 0
            let toolCallCount = assistant.events.filter {
                if case .toolCallStarted = $0 { return true }
                return false
            }.count
            let askUserPayloadCount = assistant.events.filter {
                if case .askUser = $0 { return true }
                return false
            }.count
            let decision = DeepTutorContentRouter.classifyEmptyOutput(
                message: assistant,
                finishReason: output.finishReason,
                textLen: output.text.count,
                reasoningLen: reasoningLen,
                toolCallCount: toolCallCount,
                askUserPayloadCount: askUserPayloadCount
            )
            DeepTutorChatLog.emptyOutputClassified(
                conversationID: request.conversationID,
                messageID: request.assistantMessageID,
                finishReason: output.finishReason,
                textLen: output.text.count,
                reasoningLen: reasoningLen,
                toolCallCount: toolCallCount,
                askUserPayloadCount: askUserPayloadCount,
                activePresentationSnapshot: "none",
                decision: decision
            )
        }
        assistant = assistant.replacing(status: .ready)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        await request.onAssistantUpdate(assistant)

        let cost = Date().timeIntervalSince(streamStart)
        let reasoningLength = output.reasoningText?.count ?? 0
        logger.info(
            "DeepTutor AI 流式完成，conversation=\(conversationShortID), model=\(resolvedConfig.model), finishReason=\(output.finishReason ?? "-"), textLen=\(output.text.count), reasoningLen=\(reasoningLength), assistantContent=\(DeepTutorChatLog.contentSnippet(output.text)), cost=\(DeepTutorChatLog.format(cost))s",
            module: DeepTutorChatLog.module
        )

        return StreamResult(
            output: output,
            assistantMessage: assistant,
            resolvedModel: resolvedConfig.model,
            resolvedProvider: resolvedConfig.source.rawValue,
            resolvedSource: resolvedConfig.source.rawValue,
            resolvedEndpoint: resolvedConfig.endpoint.absoluteString
        )
    }

    struct ResumeStreamRequest: Sendable {
        let conversationID: UUID
        let capability: DeepTutorCapability
        let conversationTitle: String
        let settings: DeepTutorConversationGenerationSettings
        let visibleHistory: [DeepTutorMessage]
        let assistantMessage: DeepTutorMessage
        let resumeContext: DeepTutorAskUserResumeContext
        let priorToolSnapshot: DeepTutorPerTurnToolSnapshot?
        let session: DeepTutorGenerationSession
        let onAssistantUpdate: @Sendable (DeepTutorMessage) async -> Void
    }

    func resumeStream(_ request: ResumeStreamRequest) async throws -> StreamResult {
        let conversationShortID = DeepTutorChatLog.shortID(request.conversationID)
        logger.info(
            "DeepTutor AI 追问恢复推理开始，conversation=\(conversationShortID), assistant=\(DeepTutorChatLog.shortID(request.assistantMessage.id)), toolCall=\(request.resumeContext.toolCallID)",
            module: DeepTutorChatLog.module
        )

        let resolvedConfig = try await aiConfigCenter.resolve(
            for: .chat,
            preferredModelName: request.settings.currentModelName
        )

        var mountContext = DeepTutorToolMountContext.default(
            capability: request.capability,
            userInput: request.resumeContext.originalUserPrompt,
            conversationID: request.conversationID,
            conversationTitle: request.conversationTitle
        )
        let toolPolicy = DeepTutorToolPolicyResolver.resolveForAskUserResume(
            context: mountContext,
            originalUserPrompt: request.resumeContext.originalUserPrompt,
            answerSummary: request.resumeContext.answerSummary,
            priorSnapshot: request.priorToolSnapshot
        )
        mountContext.userInput = "\(request.resumeContext.originalUserPrompt)\n\(request.resumeContext.answerSummary)"

        DeepTutorChatLog.toolIntentDetected(
            conversationID: request.conversationID,
            intentHints: toolPolicy.intentHints,
            structuredIntents: toolPolicy.structuredIntents
        )
        DeepTutorChatLog.domainToolExtensionResolved(
            conversationID: request.conversationID,
            results: toolPolicy.domainExtensionResults
        )
        DeepTutorChatLog.healthDataEligibility(
            conversationID: request.conversationID,
            eligible: toolPolicy.healthDataEligible,
            reason: toolPolicy.healthDataIneligibleReason,
            hasSelectedMember: mountContext.hasSelectedMember
        )
        DeepTutorChatLog.toolPolicyHealthSurface(
            conversationID: request.conversationID,
            policy: toolPolicy
        )

        let healthPromptMode = DeepTutorPromptBuilder.healthPromptMode(
            allowedToolNames: toolPolicy.allowedToolNames
        )
        let prompt = DeepTutorPromptBuilder.build(
            capability: request.capability,
            conversationTitle: request.conversationTitle,
            rolePrompt: nil,
            healthPromptMode: healthPromptMode
        )
        let inference = ChatOrchestratorInferenceOptions(
            useTools: toolPolicy.useTools,
            useKnowledgeBag: toolPolicy.useKnowledgeBag,
            useWebSearch: toolPolicy.useWebSearch,
            reasoningEnabled: true,
            reasoningEffortTier: 1,
            allowedToolNames: toolPolicy.allowedToolNames
        )

        DeepTutorChatLog.toolPolicyResolved(
            conversationID: request.conversationID,
            assistantMessageID: request.assistantMessage.id,
            capability: request.capability,
            inputLength: request.resumeContext.answerSummary.count,
            policy: toolPolicy,
            modelSupportsToolCalling: true
        )

        let resumeLoopMessages = DeepTutorAskUserResumeBuilder.buildLoopMessages(
            systemPrompt: prompt.systemPrompt,
            visibleHistory: request.visibleHistory,
            context: request.resumeContext
        )

        let accumulator = DeepTutorAIRuntimeStreamAccumulator(assistant: request.assistantMessage)
        let streamStart = Date()
        let cancellationToken = await request.session.cancellationToken
        let flushTracker = DeepTutorPartialFlushTracker()
        let output = try await orchestrator.generateReply(
            userInput: "",
            history: [],
            memberContextSummary: "",
            memberID: nil,
            threadID: request.conversationID,
            assistantMessageClientID: request.assistantMessage.id,
            inference: inference,
            preferredModelName: request.settings.currentModelName,
            temperature: request.settings.temperature ?? resolvedConfig.temperature,
            topP: request.settings.topP,
            maxTokens: resolvedConfig.maxTokens,
            maxMessages: request.settings.maxMessages,
            cancellationToken: cancellationToken,
            preferInlineAskUser: true,
            resumeLoopMessages: resumeLoopMessages,
            onPartial: { partial in
                guard partial.answer.isEmpty == false
                    || partial.reasoning?.isEmpty == false
                    || partial.toolName != nil else {
                    return
                }
                let mapped = await accumulator.apply(partial: partial)
                let updated = mapped.message
                let hasNewEvents = mapped.events.isEmpty == false
                let hasAskUser = Self.containsAskUserEvent(mapped.events)
                let shouldForceFlush = hasAskUser || Self.containsStructuralEvent(mapped.events)
                let shouldUpdateUI = await flushTracker.shouldFlush(
                    signature: [
                        partial.toolCallID ?? "-",
                        Self.eventSummary(mapped.events),
                        Self.blockSummary(updated.blocks),
                    ].joined(separator: "|"),
                    force: shouldForceFlush
                )
                let force = await request.session.shouldFlushUI(force: shouldForceFlush && shouldUpdateUI)
                if force {
                    await request.onAssistantUpdate(updated)
                }
            }
        )

        let completionEvents = await accumulator.completionEvents(
            output: output,
            resolvedModel: resolvedConfig.model,
            promptTokens: nil,
            completionTokens: nil,
            finishReason: output.finishReason
        )
        var assistant = await accumulator.applyCompletion(
            events: completionEvents,
            content: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        assistant = Self.salvageQuizPayloadAtCompletion(
            assistant: assistant,
            rawOutputText: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        let routedContent = DeepTutorContentRouter.finalAnswerContent(from: assistant)
        if routedContent != assistant.content {
            assistant = assistant.replacing(content: routedContent)
        }
        assistant = assistant.replacing(status: .ready)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        await request.onAssistantUpdate(assistant)

        let cost = Date().timeIntervalSince(streamStart)
        logger.info(
            "DeepTutor AI 追问恢复推理完成，conversation=\(conversationShortID), finishReason=\(output.finishReason ?? "-"), textLen=\(output.text.count), cost=\(DeepTutorChatLog.format(cost))s",
            module: DeepTutorChatLog.module
        )

        return StreamResult(
            output: output,
            assistantMessage: assistant,
            resolvedModel: resolvedConfig.model,
            resolvedProvider: resolvedConfig.source.rawValue,
            resolvedSource: resolvedConfig.source.rawValue,
            resolvedEndpoint: resolvedConfig.endpoint.absoluteString
        )
    }

    struct MemberSelectionResumeStreamRequest: Sendable {
        let conversationID: UUID
        let capability: DeepTutorCapability
        let conversationTitle: String
        let settings: DeepTutorConversationGenerationSettings
        let visibleHistory: [DeepTutorMessage]
        let assistantMessage: DeepTutorMessage
        let resumeContext: DeepTutorMemberSelectionResumeContext
        let priorToolSnapshot: DeepTutorPerTurnToolSnapshot?
        let session: DeepTutorGenerationSession
        let onAssistantUpdate: @Sendable (DeepTutorMessage) async -> Void
    }

    func resumeMemberSelectionStream(_ request: MemberSelectionResumeStreamRequest) async throws -> StreamResult {
        let conversationShortID = DeepTutorChatLog.shortID(request.conversationID)
        logger.info(
            "DeepTutor AI 成员选择恢复推理开始，conversation=\(conversationShortID), assistant=\(DeepTutorChatLog.shortID(request.assistantMessage.id)), toolCall=\(request.resumeContext.toolCallID), memberID=\(request.resumeContext.selectedMemberID)",
            module: DeepTutorChatLog.module
        )

        let resolvedConfig = try await aiConfigCenter.resolve(
            for: .chat,
            preferredModelName: request.settings.currentModelName
        )

        var mountContext = DeepTutorToolMountContext.default(
            capability: request.capability,
            userInput: request.resumeContext.originalUserPrompt,
            conversationID: request.conversationID,
            conversationTitle: request.conversationTitle
        )
        mountContext.hasSelectedMember = true
        let toolPolicy = DeepTutorToolPolicyResolver.resolveForMemberSelectionResume(
            context: mountContext,
            originalUserPrompt: request.resumeContext.originalUserPrompt,
            selectedMemberID: request.resumeContext.selectedMemberID,
            priorSnapshot: request.priorToolSnapshot
        )

        DeepTutorChatLog.toolIntentDetected(
            conversationID: request.conversationID,
            intentHints: toolPolicy.intentHints,
            structuredIntents: toolPolicy.structuredIntents
        )
        DeepTutorChatLog.domainToolExtensionResolved(
            conversationID: request.conversationID,
            results: toolPolicy.domainExtensionResults
        )
        DeepTutorChatLog.healthDataEligibility(
            conversationID: request.conversationID,
            eligible: toolPolicy.healthDataEligible,
            reason: toolPolicy.healthDataIneligibleReason,
            hasSelectedMember: true
        )
        DeepTutorChatLog.toolPolicyHealthSurface(
            conversationID: request.conversationID,
            policy: toolPolicy
        )

        let healthPromptMode = DeepTutorPromptBuilder.healthPromptMode(
            allowedToolNames: toolPolicy.allowedToolNames
        )
        let prompt = DeepTutorPromptBuilder.build(
            capability: request.capability,
            conversationTitle: request.conversationTitle,
            rolePrompt: nil,
            healthPromptMode: healthPromptMode
        )
        let inference = ChatOrchestratorInferenceOptions(
            useTools: toolPolicy.useTools,
            useKnowledgeBag: toolPolicy.useKnowledgeBag,
            useWebSearch: toolPolicy.useWebSearch,
            reasoningEnabled: true,
            reasoningEffortTier: 1,
            allowedToolNames: toolPolicy.allowedToolNames
        )

        let resumeLoopMessages = DeepTutorMemberSelectionResumeBuilder.buildLoopMessages(
            systemPrompt: prompt.systemPrompt,
            visibleHistory: request.visibleHistory,
            context: request.resumeContext
        )

        let accumulator = DeepTutorAIRuntimeStreamAccumulator(assistant: request.assistantMessage)
        let streamStart = Date()
        let cancellationToken = await request.session.cancellationToken
        let flushTracker = DeepTutorPartialFlushTracker()
        let output = try await orchestrator.generateReply(
            userInput: "",
            history: [],
            memberContextSummary: "",
            memberID: request.resumeContext.selectedMemberID,
            threadID: request.conversationID,
            assistantMessageClientID: request.assistantMessage.id,
            inference: inference,
            preferredModelName: request.settings.currentModelName,
            temperature: request.settings.temperature ?? resolvedConfig.temperature,
            topP: request.settings.topP,
            maxTokens: resolvedConfig.maxTokens,
            maxMessages: request.settings.maxMessages,
            cancellationToken: cancellationToken,
            preferInlineAskUser: true,
            preferInlineMemberSelection: true,
            resumeLoopMessages: resumeLoopMessages,
            onPartial: { partial in
                guard partial.answer.isEmpty == false
                    || partial.reasoning?.isEmpty == false
                    || partial.toolName != nil else {
                    return
                }
                let mapped = await accumulator.apply(partial: partial)
                let updated = mapped.message
                let hasAskUser = Self.containsAskUserEvent(mapped.events)
                let hasMemberSelection = Self.containsMemberSelectionEvent(mapped.events)
                let shouldForceFlush = hasAskUser || hasMemberSelection || Self.containsStructuralEvent(mapped.events)
                let shouldUpdateUI = await flushTracker.shouldFlush(
                    signature: [
                        partial.toolCallID ?? "-",
                        Self.eventSummary(mapped.events),
                        Self.blockSummary(updated.blocks),
                    ].joined(separator: "|"),
                    force: shouldForceFlush
                )
                let force = await request.session.shouldFlushUI(force: shouldForceFlush && shouldUpdateUI)
                if force {
                    await request.onAssistantUpdate(updated)
                }
            }
        )

        let completionEvents = await accumulator.completionEvents(
            output: output,
            resolvedModel: resolvedConfig.model,
            promptTokens: nil,
            completionTokens: nil,
            finishReason: output.finishReason
        )
        var assistant = await accumulator.applyCompletion(
            events: completionEvents,
            content: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        assistant = Self.salvageQuizPayloadAtCompletion(
            assistant: assistant,
            rawOutputText: DeepTutorContentSanitizer.stripLeadingInternalThinking(from: output.text)
        )
        let routedContent = DeepTutorContentRouter.finalAnswerContent(from: assistant)
        if routedContent != assistant.content {
            assistant = assistant.replacing(content: routedContent)
        }
        assistant = assistant.replacing(status: .ready)
        assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
        await request.onAssistantUpdate(assistant)

        let cost = Date().timeIntervalSince(streamStart)
        logger.info(
            "DeepTutor AI 成员选择恢复推理完成，conversation=\(conversationShortID), finishReason=\(output.finishReason ?? "-"), textLen=\(output.text.count), cost=\(DeepTutorChatLog.format(cost))s",
            module: DeepTutorChatLog.module
        )

        return StreamResult(
            output: output,
            assistantMessage: assistant,
            resolvedModel: resolvedConfig.model,
            resolvedProvider: resolvedConfig.source.rawValue,
            resolvedSource: resolvedConfig.source.rawValue,
            resolvedEndpoint: resolvedConfig.endpoint.absoluteString
        )
    }

    /// Final-turn salvage: re-run the full quiz content parser against the raw model output when
    /// streaming partial mapping stripped the payload before a summary event could be recorded.
    nonisolated private static func salvageQuizPayloadAtCompletion(
        assistant: DeepTutorMessage,
        rawOutputText: String
    ) -> DeepTutorMessage {
        guard assistant.capability == .deepQuestion else { return assistant }
        let hasSummary = assistant.events.contains { event in
            guard case let .result(metadata, summaryJSON) = event else { return false }
            return metadata["parse_failed"] != "true"
                && (summaryJSON?.isEmpty == false || metadata["summary_json"]?.isEmpty == false)
        }
        guard hasSummary == false else { return assistant }
        let source = rawOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? assistant.content
            : rawOutputText
        guard DeepTutorQuizContentParser.parse(content: source).foundStructuredPayload else {
            return assistant
        }
        return DeepTutorQuizContentParser.apply(to: assistant.replacing(content: source))
    }

    nonisolated private static func eventSummary(_ events: [DeepTutorStreamEvent]) -> String {        guard events.isEmpty == false else { return "none" }
        return events.map { event in
            switch event {
            case .contentDelta(let text, _, _): "content(\(text.count))"
            case .reasoningDelta(let text, _, _): "reasoning(\(text.count))"
            case .toolCallStarted(let callID, let toolName, _): "toolStart(\(toolName)#\(callID))"
            case .toolProgress(let callID, let label, _): "toolProgress(\(label)#\(callID))"
            case .toolResult(let callID, let payload): "toolResult(\(payload.kind)#\(callID))"
            case .askUser(let payload, let toolCallID): "askUser(q=\(payload.questions.count)#\(toolCallID))"
            case .askUserResolved(let toolCallID, let answers): "askResolved(a=\(answers.count)#\(toolCallID))"
            case .memberSelectionRequested(let reason, _, let toolCallID): "memberSelection(\(reason.count)#\(toolCallID))"
            case .memberSelectionResolved(let toolCallID, let memberID, _): "memberResolved(\(memberID)#\(toolCallID))"
            case .quizQuestionEmitted(let question, let index, _): "quiz(\(question.id)#\(index))"
            case .result(let metadata, _): "result(\(metadata["finishReason"] ?? "-"))"
            case .error: "error"
            }
        }.joined(separator: ",")
    }

    nonisolated private static func blockSummary(_ blocks: [DeepTutorMessageBlock]) -> String {
        guard blocks.isEmpty == false else { return "none" }
        let counts = Dictionary(grouping: blocks, by: \.kind).mapValues(\.count)
        return counts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")
    }
}

private actor DeepTutorPartialFlushTracker {
    private var lastSignature: String?

    func shouldFlush(signature: String, force: Bool) -> Bool {
        if force {
            if lastSignature == signature {
                return false
            }
            lastSignature = signature
            return true
        }
        guard lastSignature != signature else { return false }
        lastSignature = signature
        return true
    }
}

private actor DeepTutorToolCallLogTracker {
    enum Event: Sendable {
        case received(round: Int)
        case completed(round: Int, durationMs: Int, resultLength: Int)
    }

    private var round = 0
    private var startTimes: [String: Date] = [:]
    private var completedToolCallIDs = Set<String>()

    func record(
        toolCallID: String,
        toolInvocationArguments: [String: String]?,
        toolContent: String?,
        streamStart: Date
    ) -> Event? {
        if startTimes[toolCallID] == nil {
            round += 1
            startTimes[toolCallID] = Date()
            return .received(round: round)
        }
        if completedToolCallIDs.contains(toolCallID) == false,
           toolInvocationArguments != nil,
           toolContent?.isEmpty == false {
            completedToolCallIDs.insert(toolCallID)
            let startedAt = startTimes[toolCallID] ?? streamStart
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            return .completed(
                round: round,
                durationMs: durationMs,
                resultLength: toolContent?.count ?? 0
            )
        }
        return nil
    }
}

private actor DeepTutorAIRuntimeStreamAccumulator {
    private var mapper = DeepTutorAIRuntimeEventMapper()
    private var assistant: DeepTutorMessage

    init(assistant: DeepTutorMessage) {
        self.assistant = assistant
    }

    func events(from partial: ChatAssistantPartialDelta) -> [DeepTutorStreamEvent] {
        mapper.events(from: partial)
    }

    func apply(partial: ChatAssistantPartialDelta) -> (message: DeepTutorMessage, events: [DeepTutorStreamEvent]) {
        let events = mapper.events(from: partial)
        assistant = apply(events: events, to: assistant, content: partial.answer)
        return (assistant, events)
    }

    func completionEvents(
        output: ChatOrchestratorOutput,
        resolvedModel: String?,
        promptTokens: Int?,
        completionTokens: Int?,
        finishReason: String?
    ) -> [DeepTutorStreamEvent] {
        mapper.completionEvents(
            output: output,
            resolvedModel: resolvedModel,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            finishReason: finishReason
        )
    }

    func applyCompletion(events: [DeepTutorStreamEvent], content: String) -> DeepTutorMessage {
        assistant = apply(events: events, to: assistant, content: content)
        return assistant
    }

    func snapshot() -> DeepTutorMessage {
        assistant
    }

    private func apply(
        events: [DeepTutorStreamEvent],
        to message: DeepTutorMessage,
        content: String
    ) -> DeepTutorMessage {
        var mergedEvents = message.events
        mergedEvents.append(contentsOf: events)
        let consolidated = DeepTutorMarkdownPreserver.consolidatedContent(
            events: mergedEvents,
            runtimeAnswer: content
        )
        let updated = message.replacing(content: consolidated, events: mergedEvents, status: .streaming)
        let quizPrepared = DeepTutorQuizContentParser.applyDuringStreaming(to: updated)
        let blocked = DeepTutorMessageReducer.applyBlocks(to: quizPrepared)
        let renderMarkdown = DeepTutorMarkdownPreserver.renderMarkdownText(from: blocked)
        if renderMarkdown == blocked.content {
            return blocked
        }
        return DeepTutorMessageReducer.applyBlocks(to: blocked.replacing(content: renderMarkdown))
    }
}

private extension DeepTutorAIRuntimeAdapter {
    nonisolated static func containsAskUserEvent(_ events: [DeepTutorStreamEvent]) -> Bool {
        events.contains {
            if case .askUser = $0 { return true }
            return false
        }
    }

    nonisolated static func containsMemberSelectionEvent(_ events: [DeepTutorStreamEvent]) -> Bool {
        events.contains {
            if case .memberSelectionRequested = $0 { return true }
            return false
        }
    }

    nonisolated static func containsStructuralEvent(_ events: [DeepTutorStreamEvent]) -> Bool {
        containsOperationalEvent(events)
    }

    nonisolated static func containsOperationalEvent(_ events: [DeepTutorStreamEvent]) -> Bool {
        events.contains { event in
            switch event {
            case .contentDelta, .reasoningDelta:
                return false
            case .toolCallStarted, .toolProgress, .toolResult, .askUser, .askUserResolved,
                 .memberSelectionRequested, .memberSelectionResolved, .quizQuestionEmitted, .result, .error:
                return true
            }
        }
    }

    nonisolated static func modelSupportsToolCalling(
        modelName: String,
        bundles: AIScenarioRemoteBundlesCollection?
    ) -> Bool {
        guard let bundles else { return true }
        let allRows = bundles.allRows
        guard let selected = allRows.first(where: { $0.name == modelName }) else {
            return true
        }
        if selected.identity == AIModelIdentity.agent.rawValue,
           let baseModelName = selected.baseModelName,
           let base = allRows.first(where: { $0.name == baseModelName }) {
            return selected.supportsToolUse || base.supportsToolUse
        }
        return selected.supportsToolUse
    }
}
