import Foundation

/// Turn 编排中心：收口 model / capability / tool / prompt / snapshot 解析。
struct DeepTutorTurnCoordinator: Sendable {
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    func prepareSend(
        conversationID: UUID,
        text: String,
        capability: DeepTutorCapability,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        boundMemberID: Int?,
        requestedCanonicalTools: [String]?,
        attachments: [DeepTutorAttachment]
    ) async throws -> DeepTutorTurnPlan {
        let turnID = UUID()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        let modelContext = try DeepTutorModelContextResolver.resolve(
            bundles: bundles,
            conversation: conversation,
            snapshot: nil,
            composerSelectedModelName: settings.currentModelName ?? conversation?.currentModelName,
            mode: .liveSend
        )
        let resolvedConfig = try await aiConfigCenter.resolve(
            for: .chat,
            preferredModelName: modelContext.selectedModelName
        )
        let mountContext = makeMountContext(
            capability: capability,
            userInput: trimmed,
            conversationID: conversationID,
            conversationTitle: conversationTitle,
            boundMemberID: boundMemberID,
            requestedCanonicalTools: requestedCanonicalTools,
            attachments: attachments,
            configSnapshot: try await aiConfigCenter.currentSnapshot()
        )
        let builtRequest = DeepTutorRuntimeRequestBuilder.build(
            userInput: trimmed,
            capability: capability,
            conversationID: conversationID,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            modelContext: modelContext,
            visibleHistory: visibleHistory,
            resolvedConfigMaxTokens: resolvedConfig.maxTokens,
            mountContext: mountContext
        )
        let snapshot = makeSnapshot(
            turnID: turnID,
            capability: capability,
            capabilityStage: capability.initialStage,
            resumeMode: DeepTutorTurnResumeMode.liveSend,
            modelResolutionMode: DeepTutorModelContextResolver.ResolutionMode.liveSend,
            mountContext: mountContext,
            builtRequest: builtRequest,
            modelContext: modelContext,
            attachments: attachments,
            configSnapshot: try await aiConfigCenter.currentSnapshot()
        )
        logTurnPlanPrepared(
            conversationID: conversationID,
            turnID: turnID,
            capability: capability,
            resumeMode: DeepTutorTurnResumeMode.liveSend,
            modelContext: modelContext,
            finalTools: builtRequest.finalAllowedToolNames
        )
        return DeepTutorTurnPlan(
            turnID: turnID,
            conversationID: conversationID,
            capability: capability,
            capabilityStage: capability.initialStage,
            resumeMode: DeepTutorTurnResumeMode.liveSend,
            modelResolutionMode: DeepTutorModelContextResolver.ResolutionMode.liveSend,
            intent: .send(userText: trimmed),
            modelContext: modelContext,
            builtRequest: builtRequest,
            snapshot: snapshot,
            conversation: conversation,
            settings: settings,
            conversationTitle: conversationTitle,
            userInput: trimmed,
            visibleHistory: visibleHistory,
            boundMemberID: boundMemberID
        )
    }

    func prepareRetry(
        conversationID: UUID,
        assistantMessageID: UUID,
        userMessageID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        userMessage: DeepTutorMessage,
        boundMemberID: Int?
    ) async throws -> DeepTutorTurnPlan {
        try await prepareReplay(
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            visibleHistory: visibleHistory,
            userMessage: userMessage,
            intent: .retryAssistant(assistantMessageID: assistantMessageID, userMessageID: userMessageID),
            boundMemberID: boundMemberID
        )
    }

    func prepareRegenerate(
        conversationID: UUID,
        assistantMessageID: UUID,
        userMessageID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        userMessage: DeepTutorMessage,
        boundMemberID: Int?
    ) async throws -> DeepTutorTurnPlan {
        try await prepareReplay(
            conversationID: conversationID,
            capability: capability,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            visibleHistory: visibleHistory,
            userMessage: userMessage,
            intent: .regenerate(assistantMessageID: assistantMessageID, userMessageID: userMessageID),
            boundMemberID: boundMemberID
        )
    }

    private func prepareReplay(
        conversationID: UUID,
        capability: DeepTutorCapability,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        userMessage: DeepTutorMessage,
        intent: DeepTutorTurnPlan.Intent,
        boundMemberID: Int?
    ) async throws -> DeepTutorTurnPlan {
        let turnID = UUID()
        let replaySnapshot = userMessage.requestSnapshot
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        let modelContext = try DeepTutorModelContextResolver.resolve(
            bundles: bundles,
            conversation: conversation,
            snapshot: replaySnapshot,
            composerSelectedModelName: settings.currentModelName ?? conversation?.currentModelName,
            mode: .replaySnapshot
        )
        let effectiveCapability = replaySnapshot?.capability ?? capability
        let capabilityStage = replaySnapshot?.capabilityStage
            .flatMap(DeepTutorCapabilityStage.init(rawValue:))
            ?? effectiveCapability.initialStage
        var snapshot = replaySnapshot ?? DeepTutorRequestSnapshot(capability: effectiveCapability)
        snapshot = snapshot.appendingTurnEnvelope(
            turnID: turnID,
            resumeMode: .replaySnapshot,
            capabilityStage: capabilityStage,
            modelResolutionMode: .replaySnapshot
        )
        logTurnPlanPrepared(
            conversationID: conversationID,
            turnID: turnID,
            capability: effectiveCapability,
            resumeMode: .replaySnapshot,
            modelContext: modelContext,
            finalTools: Set(snapshot.finalAllowedToolNames ?? [])
        )
        return DeepTutorTurnPlan(
            turnID: turnID,
            conversationID: conversationID,
            capability: effectiveCapability,
            capabilityStage: capabilityStage,
            resumeMode: .replaySnapshot,
            modelResolutionMode: .replaySnapshot,
            intent: intent,
            modelContext: modelContext,
            builtRequest: nil,
            snapshot: snapshot,
            conversation: conversation,
            settings: settings,
            conversationTitle: conversationTitle,
            userInput: userMessage.content,
            visibleHistory: visibleHistory,
            boundMemberID: boundMemberID
        )
    }

    private func makeMountContext(
        capability: DeepTutorCapability,
        userInput: String,
        conversationID: UUID,
        conversationTitle: String,
        boundMemberID: Int?,
        requestedCanonicalTools: [String]?,
        attachments: [DeepTutorAttachment],
        configSnapshot: AISettingsSnapshot
    ) -> DeepTutorToolMountContext {
        var mountContext = DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: conversationID,
            conversationTitle: conversationTitle
        )
        mountContext.hasSelectedMember = boundMemberID != nil && (boundMemberID ?? 0) > 0
        mountContext.hasLocationPermission = SparkLocationService.hasWhenInUsePermission()
        mountContext.weatherToolEnabled = configSnapshot.weatherToolPreferences.useWeather
        mountContext.hasAttachment = attachments.isEmpty == false
        if let requestedCanonicalTools {
            mountContext.snapshotRequestedTools = requestedCanonicalTools
        }
        if capability == .deepQuestion {
            mountContext.toolPhase = .explore
        }
        return mountContext
    }

    private func makeSnapshot(
        turnID: UUID,
        capability: DeepTutorCapability,
        capabilityStage: DeepTutorCapabilityStage,
        resumeMode: DeepTutorTurnResumeMode,
        modelResolutionMode: DeepTutorModelContextResolver.ResolutionMode,
        mountContext: DeepTutorToolMountContext,
        builtRequest: DeepTutorRuntimeRequestBuilder.BuiltRequest,
        modelContext: DeepTutorResolvedModelContext,
        attachments: [DeepTutorAttachment],
        configSnapshot: AISettingsSnapshot
    ) -> DeepTutorRequestSnapshot {
        let baseSnapshot = DeepTutorToolPolicyResolver.makePerTurnSnapshot(
            for: mountContext,
            policy: builtRequest.toolPolicy,
            attachments: attachments,
            searchConfigRevision: configSnapshot.searchConfigRevision
        )
        return baseSnapshot
            .appendingModelContext(
                modelContext,
                finalAllowedToolNames: builtRequest.finalAllowedToolNames,
                promptSource: builtRequest.promptSource,
                resolvedTemperature: builtRequest.temperature,
                resolvedMaxTokens: builtRequest.maxTokens
            )
            .appendingTurnEnvelope(
                turnID: turnID,
                resumeMode: resumeMode,
                capabilityStage: capabilityStage,
                modelResolutionMode: modelResolutionMode
            )
    }

    private func logTurnPlanPrepared(
        conversationID: UUID,
        turnID: UUID,
        capability: DeepTutorCapability,
        resumeMode: DeepTutorTurnResumeMode,
        modelContext: DeepTutorResolvedModelContext,
        finalTools: Set<String>
    ) {
        DeepTutorChatLog.turnPlanPrepared(
            conversationID: conversationID,
            turnID: turnID,
            capability: capability.rawValue,
            stage: capability.initialStage.rawValue,
            resumeMode: resumeMode.rawValue,
            selectedModel: modelContext.selectedModelName,
            identity: modelContext.identity.rawValue,
            promptSource: modelContext.promptSource.rawValue,
            finalToolCount: finalTools.count
        )
        logger.info(
            "DeepTutor turn plan prepared，conversation=\(DeepTutorChatLog.shortID(conversationID)), turn=\(DeepTutorChatLog.shortID(turnID)), capability=\(capability.rawValue), resume=\(resumeMode.rawValue), model=\(modelContext.selectedModelName), tools=\(finalTools.count)",
            module: DeepTutorChatLog.module
        )
    }
}
