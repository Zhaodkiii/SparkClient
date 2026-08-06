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
        let preferredModelName: String?
        let temperature: Double?
        let topP: Double?
        let maxMessages: Int?
    }

    nonisolated static func build(
        userInput: String,
        capability: DeepTutorCapability,
        conversationID: UUID,
        conversationTitle: String,
        settings: DeepTutorConversationGenerationSettings,
        visibleHistory: [DeepTutorMessage],
        preferredModelName: String? = nil,
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

        let toolPolicy = DeepTutorToolPolicyResolver.resolve(resolvedMountContext)
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

        let healthPromptMode = DeepTutorPromptBuilder.healthPromptMode(
            allowedToolNames: toolPolicy.allowedToolNames
        )
        let weatherPromptMode = DeepTutorPromptBuilder.weatherPromptMode(
            allowedToolNames: toolPolicy.allowedToolNames
        )
        let prompt = DeepTutorPromptBuilder.build(
            capability: capability,
            conversationTitle: conversationTitle,
            rolePrompt: nil,
            healthPromptMode: healthPromptMode,
            weatherPromptMode: weatherPromptMode
        )
        let promptSchemaMismatches = DeepTutorPromptSchemaConsistencyChecker.mismatchedTools(
            prompt: prompt.systemPrompt,
            schemaNames: DeepTutorToolPolicyResolver.effectiveToolSchemaNames(
                inference: ChatOrchestratorInferenceOptions(
                    useTools: toolPolicy.useTools,
                    useKnowledgeBag: toolPolicy.useKnowledgeBag,
                    useWebSearch: toolPolicy.useWebSearch,
                    reasoningEnabled: true,
                    reasoningEffortTier: 1,
                    allowedToolNames: toolPolicy.allowedToolNames
                )
            )
        )
        if promptSchemaMismatches.isEmpty == false {
            DeepTutorChatLog.toolPolicyPromptSchemaMismatch(
                conversationID: conversationID,
                mismatchedTools: promptSchemaMismatches
            )
        }

        let inference = ChatOrchestratorInferenceOptions(
            useTools: toolPolicy.useTools,
            useKnowledgeBag: toolPolicy.useKnowledgeBag,
            useWebSearch: toolPolicy.useWebSearch,
            reasoningEnabled: true,
            reasoningEffortTier: 1,
            allowedToolNames: toolPolicy.allowedToolNames
        )

        let history = visibleHistory
            .filter { $0.role != .system && $0.isDeleted == false }
            .map(chatMessage(from:))

        let resolvedPreferred = preferredModelName
            ?? settings.currentModelName

        return BuiltRequest(
            history: history,
            systemPrompt: prompt.systemPrompt,
            inference: inference,
            toolPolicy: toolPolicy,
            preferredModelName: resolvedPreferred,
            temperature: settings.temperature,
            topP: settings.topP,
            maxMessages: settings.maxMessages
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
