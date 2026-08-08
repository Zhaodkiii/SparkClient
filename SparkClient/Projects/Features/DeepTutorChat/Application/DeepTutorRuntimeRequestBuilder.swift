import Foundation

/// DeepTutor 会话级生成参数（来自 CoreData thread 字段）。
nonisolated struct DeepTutorConversationGenerationSettings: Equatable, Sendable {
    var currentModelName: String?
    var temperature: Double?
    var topP: Double?
    var maxMessages: Int?

    nonisolated static let `default` = DeepTutorConversationGenerationSettings(
        currentModelName: nil,
        temperature: nil,
        topP: 1.0,
        maxMessages: 20
    )
}

enum DeepTutorRuntimeRequestBuilder: Sendable {
    struct BuiltRequest: Sendable {
        let history: [ChatMessage]
        let systemPrompt: String
        let inference: ChatOrchestratorInferenceOptions
        let toolPolicy: DeepTutorToolPolicyResult
        let preferredModelName: String
        let temperature: Double?
        let topP: Double?
        let maxTokens: Int?
        let maxMessages: Int?
        let modelContext: DeepTutorResolvedModelContext
        let promptSource: DeepTutorPromptSource
        let finalAllowedToolNames: Set<String>
        let toolMergeReason: String
    }

    struct FinalizedInferencePrompt: Sendable {
        let toolPolicy: DeepTutorToolPolicyResult
        let finalAllowedToolNames: Set<String>
        let systemPrompt: String
        let inference: ChatOrchestratorInferenceOptions
        let promptSource: DeepTutorPromptSource
        let temperature: Double?
        let maxTokens: Int?
        let maxMessages: Int?
        let toolMergeReason: String
    }

    nonisolated static func finalize(
        baseToolPolicy: DeepTutorToolPolicyResult,
        modelContext: DeepTutorResolvedModelContext,
        capability: DeepTutorCapability,
        conversationID: UUID,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        resolvedConfigMaxTokens: Int?
    ) -> FinalizedInferencePrompt {
        let modelRestriction = DeepTutorModelToolRestrictionResolver.restriction(
            from: modelContext.aiToolScenarios
        )
        let merged = DeepTutorModelToolMerger.merge(
            deepTutorPolicy: baseToolPolicy,
            modelRestriction: modelRestriction
        )
        let toolPolicy = merged.policy
        let finalAllowedToolNames = merged.finalAllowedToolNames

        DeepTutorChatLog.modelToolPolicyMerged(
            conversationID: conversationID,
            deepTutorTools: baseToolPolicy.allowedToolNames.sorted(),
            modelTools: modelContext.modelAllowedToolNames?.sorted() ?? [],
            finalTools: finalAllowedToolNames.sorted(),
            reason: merged.mergeReason
        )

        let healthPromptMode = DeepTutorPromptBuilder.healthPromptMode(
            allowedToolNames: finalAllowedToolNames,
            hasBoundMember: conversation?.memberID != nil
        )
        let weatherPromptMode = DeepTutorPromptBuilder.weatherPromptMode(
            allowedToolNames: finalAllowedToolNames
        )
        let promptBuilt = DeepTutorPromptMerger.buildSystemPrompt(
            context: modelContext,
            capability: capability,
            conversationTitle: conversationTitle,
            sessionPrompt: conversation?.rolePrompt,
            healthPromptMode: healthPromptMode,
            weatherPromptMode: weatherPromptMode
        )
        DeepTutorChatLog.promptResolved(
            conversationID: conversationID,
            source: promptBuilt.promptSource.rawValue,
            identity: modelContext.identity.rawValue,
            capability: capability.rawValue,
            finalLength: promptBuilt.systemPrompt.count
        )

        let inference = ChatOrchestratorInferenceOptions(
            useTools: toolPolicy.useTools,
            useKnowledgeBag: toolPolicy.useKnowledgeBag,
            useWebSearch: toolPolicy.useWebSearch,
            reasoningEnabled: true,
            reasoningEffortTier: 1,
            allowedToolNames: finalAllowedToolNames
        )

        let generation = DeepTutorModelContextResolver.generationParameters(
            context: modelContext,
            conversation: conversation,
            resolvedConfigMaxTokens: resolvedConfigMaxTokens
        )

        return FinalizedInferencePrompt(
            toolPolicy: toolPolicy,
            finalAllowedToolNames: finalAllowedToolNames,
            systemPrompt: promptBuilt.systemPrompt,
            inference: inference,
            promptSource: promptBuilt.promptSource,
            temperature: generation.temperature,
            maxTokens: generation.maxTokens,
            maxMessages: generation.maxMessages,
            toolMergeReason: merged.mergeReason
        )
    }

    nonisolated static func build(
        userInput: String,
        capability: DeepTutorCapability,
        conversationID: UUID,
        conversationTitle: String,
        conversation: DeepTutorConversation?,
        settings: DeepTutorConversationGenerationSettings,
        modelContext: DeepTutorResolvedModelContext,
        visibleHistory: [DeepTutorMessage],
        resolvedConfigMaxTokens: Int? = nil,
        mountContext: DeepTutorToolMountContext? = nil
    ) -> BuiltRequest {
        var resolvedMountContext = mountContext ?? DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: conversationID,
            conversationTitle: conversationTitle
        )
        resolvedMountContext.userInput = userInput
        resolvedMountContext.capability = capability
        resolvedMountContext.conversationID = conversationID
        resolvedMountContext.conversationTitle = conversationTitle

        let baseToolPolicy = DeepTutorToolPolicyResolver.resolve(resolvedMountContext)
        let finalized = finalize(
            baseToolPolicy: baseToolPolicy,
            modelContext: modelContext,
            capability: capability,
            conversationID: conversationID,
            conversationTitle: conversationTitle,
            conversation: conversation,
            settings: settings,
            resolvedConfigMaxTokens: resolvedConfigMaxTokens
        )
        let toolPolicy = finalized.toolPolicy
        let finalAllowedToolNames = finalized.finalAllowedToolNames

        DeepTutorChatLog.toolPolicyCompose(
            conversationID: conversationID,
            requestedTools: toolPolicy.requestedCanonicalTools,
            autoMountedTools: toolPolicy.autoMountedCanonicalTools,
            resolvedTools: toolPolicy.resolvedCanonicalTools,
            aliasFailures: toolPolicy.aliasFailures,
            intentHints: toolPolicy.intentHints
        )
        DeepTutorChatLog.toolIntentDetected(
            conversationID: conversationID,
            intentHints: toolPolicy.intentHints,
            structuredIntents: toolPolicy.structuredIntents
        )
        DeepTutorChatLog.domainToolExtensionResolved(
            conversationID: conversationID,
            results: toolPolicy.domainExtensionResults
        )
        DeepTutorChatLog.healthDataEligibility(
            conversationID: conversationID,
            eligible: toolPolicy.healthDataEligible,
            reason: toolPolicy.healthDataIneligibleReason,
            hasSelectedMember: resolvedMountContext.hasSelectedMember
        )
        DeepTutorChatLog.toolPolicyHealthSurface(
            conversationID: conversationID,
            policy: toolPolicy
        )

        let promptSchemaMismatches = DeepTutorPromptSchemaConsistencyChecker.mismatchedTools(
            prompt: finalized.systemPrompt,
            schemaNames: DeepTutorToolPolicyResolver.effectiveToolSchemaNames(inference: finalized.inference)
        )
        if promptSchemaMismatches.isEmpty == false {
            DeepTutorChatLog.toolPolicyPromptSchemaMismatch(
                conversationID: conversationID,
                mismatchedTools: promptSchemaMismatches
            )
        }

        let history = visibleHistory
            .filter { $0.role != .system && $0.isDeleted == false }
            .map(chatMessage(from:))

        return BuiltRequest(
            history: history,
            systemPrompt: finalized.systemPrompt,
            inference: finalized.inference,
            toolPolicy: toolPolicy,
            preferredModelName: modelContext.selectedModelName,
            temperature: finalized.temperature,
            topP: settings.topP,
            maxTokens: finalized.maxTokens,
            maxMessages: finalized.maxMessages,
            modelContext: modelContext,
            promptSource: finalized.promptSource,
            finalAllowedToolNames: finalAllowedToolNames,
            toolMergeReason: finalized.toolMergeReason
        )
    }

    nonisolated static func chatMessage(from message: DeepTutorMessage) -> ChatMessage {
        var blocks: [ChatMessageBlock] = []
        if message.content.isEmpty == false {
            blocks.append(
                ChatMessageBlock(
                    kind: .text,
                    text: message.content
                )
            )
        }

        let chatAttachments = message.attachments.compactMap { $0.toChatAttachment() }
        let imageAttachments = chatAttachments.filter { $0.type == .image }
        let fileAttachments = chatAttachments.filter { $0.type == .pdf || $0.type == .file }
        if imageAttachments.isEmpty == false {
            blocks.append(
                ChatMessageBlock(
                    kind: .imageGallery,
                    attachments: imageAttachments
                )
            )
        }
        if fileAttachments.isEmpty == false {
            blocks.append(
                ChatMessageBlock(
                    kind: .fileAttachments,
                    attachments: fileAttachments
                )
            )
        }

        return ChatMessage(
            threadID: message.conversationID,
            role: message.role == .user ? .user : .assistant,
            blocks: blocks,
            clientMessageID: message.id,
            deliveryState: message.status == .failed ? .failed : .sent,
            createdAt: message.createdAt
        )
    }

    nonisolated static func userFacingConfigError(_ error: Error) -> String {
        if let configError = error as? AIConfigError {
            switch configError {
            case .missingModelForScenario(let scenario):
                return "请先在 AI 设置中配置 \(scenario.rawValue) 场景的可用模型。"
            case .missingScenario(let scenario):
                return "未找到场景 \(scenario.rawValue) 的 AI 配置，请打开 AI 设置。"
            case .invalidEndpoint(let endpoint):
                return "AI 模型 endpoint 无效：\(endpoint)"
            case .runtimeNotBootstrapped:
                return "AI 运行环境尚未就绪，请稍后重试或打开 AI 设置。"
            }
        }
        if error is CancellationError {
            return "生成已取消。"
        }
        return error.localizedDescription
    }
}
