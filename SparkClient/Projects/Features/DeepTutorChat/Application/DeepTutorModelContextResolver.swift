import Foundation

nonisolated enum DeepTutorPromptSource: String, Codable, Sendable {
    case smallTask
    case agent
    case session
    case deepTutorDefault
}

nonisolated struct DeepTutorResolvedModelContext: Sendable, Equatable {
    let selectedModelName: String
    let identity: AIModelIdentity
    let displayTitle: String
    let baseModelName: String?
    let systemPrompt: String?
    let aiToolScenarios: [String]
    let supportsToolUse: Bool
    let supportsMultimodal: Bool
    let temperature: Double
    let maxTokens: Int
    let promptSource: DeepTutorPromptSource
    let modelAllowedToolNames: Set<String>?
}

nonisolated struct DeepTutorModelToolRestriction: Equatable, Sendable {
    let allowedToolNames: Set<String>?
    let reason: String
}

nonisolated enum DeepTutorModelToolRestrictionResolver {
    /// 与 Chat `SendChatMessageUseCase.allowedToolNames(from:)` 语义一致。
    nonisolated static func restriction(from storedToolNames: [String]) -> DeepTutorModelToolRestriction {
        if storedToolNames.isEmpty {
            return DeepTutorModelToolRestriction(allowedToolNames: nil, reason: "model_whitelist_unrestricted")
        }
        if storedToolNames.contains(SparkToolName.noSelectionSentinel) {
            return DeepTutorModelToolRestriction(allowedToolNames: [], reason: "model_whitelist_none")
        }
        let normalized = Set(storedToolNames).intersection(Set(SparkToolName.all))
        if normalized.isEmpty {
            return DeepTutorModelToolRestriction(allowedToolNames: nil, reason: "model_whitelist_unrestricted")
        }
        return DeepTutorModelToolRestriction(
            allowedToolNames: normalized,
            reason: "model_whitelist_explicit"
        )
    }
}

nonisolated enum DeepTutorModelToolMerger {
    nonisolated static func merge(
        deepTutorPolicy: DeepTutorToolPolicyResult,
        modelRestriction: DeepTutorModelToolRestriction
    ) -> (policy: DeepTutorToolPolicyResult, finalAllowedToolNames: Set<String>, mergeReason: String) {
        guard deepTutorPolicy.useTools else {
            return (deepTutorPolicy, [], "deeptutor_tools_disabled")
        }

        let deepTutorAllowed = deepTutorPolicy.allowedToolNames
        guard let modelAllowed = modelRestriction.allowedToolNames else {
            return (deepTutorPolicy, deepTutorAllowed, modelRestriction.reason)
        }
        if modelAllowed.isEmpty {
            var disabled = deepTutorPolicy
            disabled.useTools = false
            disabled.useKnowledgeBag = false
            disabled.useWebSearch = false
            disabled.allowedToolNames = []
            disabled.policyReason = "\(deepTutorPolicy.policyReason);model_whitelist_none"
            return (disabled, [], "model_whitelist_none")
        }

        let intersection = deepTutorAllowed.intersection(modelAllowed)
        var merged = deepTutorPolicy
        merged.allowedToolNames = intersection
        merged.useKnowledgeBag = intersection.contains(SparkToolName.searchKnowledgeBag.rawValue)
            || intersection.contains(SparkToolName.createKnowledgeDocument.rawValue)
        let webTools: Set<String> = [
            SparkToolName.searchOnline.rawValue,
            SparkToolName.readWebPage.rawValue,
            SparkToolName.searchArxivPapers.rawValue,
            SparkToolName.extractRemoteFileContent.rawValue,
        ]
        merged.useWebSearch = intersection.isDisjoint(with: webTools) == false
        merged.useTools = intersection.isEmpty == false
        merged.policyReason = "\(deepTutorPolicy.policyReason);model_whitelist_intersection"
        let mergeReason = intersection.isEmpty ? "model_whitelist_empty_intersection" : modelRestriction.reason
        return (merged, intersection, mergeReason)
    }
}

nonisolated enum DeepTutorModelContextResolver {
    nonisolated enum ResolutionMode: Sendable {
        case liveSend
        case replaySnapshot
    }

    nonisolated static func resolve(
        bundles: AIScenarioRemoteBundlesCollection,
        conversation: DeepTutorConversation?,
        snapshot: DeepTutorRequestSnapshot?,
        composerSelectedModelName: String?,
        mode: ResolutionMode = .liveSend
    ) throws -> DeepTutorResolvedModelContext {
        let preferredName: String?
        switch mode {
        case .replaySnapshot:
            preferredName = normalized(snapshot?.selectedModelName)
                ?? normalized(composerSelectedModelName)
                ?? normalized(conversation?.currentModelName)
        case .liveSend:
            preferredName = normalized(composerSelectedModelName)
                ?? normalized(conversation?.currentModelName)
        }

        guard let row = bundles.resolveRow(for: .chat, preferredModelName: preferredName) else {
            throw AIConfigError.missingModelForScenario(.chat)
        }

        let identity = AIModelIdentity(rawValue: row.identity) ?? .model
        let modelRestriction = DeepTutorModelToolRestrictionResolver.restriction(from: row.aiToolScenarios)
        let promptSource = resolvePromptSource(identity: identity, row: row, conversation: conversation)

        return DeepTutorResolvedModelContext(
            selectedModelName: row.name,
            identity: identity,
            displayTitle: row.displayTitle,
            baseModelName: row.baseModelName,
            systemPrompt: row.systemPrompt,
            aiToolScenarios: row.aiToolScenarios,
            supportsToolUse: row.supportsToolUse,
            supportsMultimodal: row.supportsMultimodal,
            temperature: row.temperature,
            maxTokens: row.maxTokens,
            promptSource: promptSource,
            modelAllowedToolNames: modelRestriction.allowedToolNames
        )
    }

    nonisolated static func generationParameters(
        context: DeepTutorResolvedModelContext,
        conversation: DeepTutorConversation?,
        resolvedConfigMaxTokens: Int?
    ) -> (temperature: Double?, maxTokens: Int?, maxMessages: Int?) {
        let maxMessages = conversation?.maxMessages ?? DeepTutorConversationGenerationSettings.default.maxMessages
        if context.identity == .agent {
            return (context.temperature, context.maxTokens, maxMessages)
        }
        let temperature = conversation?.temperature ?? context.temperature
        let maxTokens = context.maxTokens > 0 ? context.maxTokens : resolvedConfigMaxTokens
        return (temperature, maxTokens, maxMessages)
    }

    nonisolated static func resolvedRow(
        bundles: AIScenarioRemoteBundlesCollection,
        preferredModelName: String?
    ) -> AIScenarioRemoteModelRow? {
        bundles.resolveRow(for: .chat, preferredModelName: normalized(preferredModelName))
    }

    nonisolated private static func resolvePromptSource(
        identity: AIModelIdentity,
        row: AIScenarioRemoteModelRow,
        conversation: DeepTutorConversation?
    ) -> DeepTutorPromptSource {
        if identity == .agent, row.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return .agent
        }
        if normalized(conversation?.rolePrompt)?.isEmpty == false {
            return .session
        }
        return .deepTutorDefault
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension DeepTutorRequestSnapshot {
    func appendingModelContext(
        _ context: DeepTutorResolvedModelContext,
        finalAllowedToolNames: Set<String>,
        promptSource: DeepTutorPromptSource,
        resolvedTemperature: Double?,
        resolvedMaxTokens: Int?
    ) -> DeepTutorRequestSnapshot {
        var copy = self
        copy.selectedModelName = context.selectedModelName
        copy.selectedModelIdentity = context.identity.rawValue
        copy.selectedAgentBaseModelName = context.baseModelName
        copy.modelAllowedToolNames = context.modelAllowedToolNames?.sorted()
        copy.finalAllowedToolNames = finalAllowedToolNames.sorted()
        copy.promptSource = promptSource.rawValue
        copy.resolvedTemperature = resolvedTemperature
        copy.resolvedMaxTokens = resolvedMaxTokens
        return copy
    }

    func appendingTurnEnvelope(
        turnID: UUID,
        resumeMode: DeepTutorTurnResumeMode,
        capabilityStage: DeepTutorCapabilityStage,
        modelResolutionMode: DeepTutorModelContextResolver.ResolutionMode
    ) -> DeepTutorRequestSnapshot {
        var copy = self
        copy.turnID = turnID
        copy.resumeMode = resumeMode.rawValue
        copy.capabilityStage = capabilityStage.rawValue
        copy.modelResolutionMode = modelResolutionMode == .replaySnapshot ? "replay_snapshot" : "live_send"
        return copy
    }
}
