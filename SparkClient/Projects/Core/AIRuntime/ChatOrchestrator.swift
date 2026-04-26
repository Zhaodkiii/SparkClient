import Foundation
import UIKit

/// 对话编排模块的输出结果
/// 承载模型最终返回的文本、推理内容、结束原因、工具调用等完整输出信息
struct ChatOrchestratorOutput: Sendable {
    /// 最终返回给用户的消息主体文本
    let text: String
    
    /// 模型思考/推理过程文本（Chain-of-Thought / Reasoning）
    let reasoningText: String?
    
    /// 模型推理耗时（单位：毫秒）
    let reasoningDurationMs: Int64?
    
    /// 模型生成结束原因（如：stop / length / tool_calls 等）
    let finishReason: String?
    
    /// 消息类型（文本/图片/卡片/结构化数据等）
    let kind: ChatMessageKind
    
    /// 调用的工具名称（如果当前输出由工具执行产生）
    let toolName: String?
    
    /// 工具执行的内容/参数（JSON 或结构化文本）
    let toolContent: String?
}
/// 助手流式回调的标准增量模型。
/// 统一承载“正文 / 推理 / 工具链路”字段，避免多参数回调扩散。
struct ChatAssistantPartialDelta: Sendable {
    let answer: String
    let reasoning: String?
    let kind: ChatMessageKind
    let toolName: String?
    let toolContent: String?
}

struct ChatOrchestrator: Sendable {
    let runtimeService: any AIRuntimeServing
    let toolHub: ToolHub
    let consentGate: ConsentGate
    let fileCacheManager: FileCacheManager
    let logger: Logger

    init(
        runtimeService: any AIRuntimeServing,
        toolHub: ToolHub,
        consentGate: ConsentGate,
        fileCacheManager: FileCacheManager,
        logger: Logger = ConsoleLogger()
    ) {
        self.runtimeService = runtimeService
        self.toolHub = toolHub
        self.consentGate = consentGate
        self.fileCacheManager = fileCacheManager
        self.logger = logger
    }

    func generateReply(
        userInput: String,
        history: [ChatMessage],
        memberContextSummary: String,
        memberID: Int?,
        threadID: UUID? = nil,
        assistantMessageClientID: UUID? = nil,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        systemPrompt: String? = nil,
        preferredModelName: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        maxMessages: Int? = nil,
        cancellationToken: AIRuntimeCancellationToken? = nil,
        /// 为 `true` 时，用户消息中的 `image_url` 附件编码为多模态 `content` 数组；否则仅使用 `ChatMessage.content` 字符串。
        deliverMultimodalImages: Bool = false,
        /// 网关单点编码（如厂商对 `image_url` 形式的差异）。
        providerCompanyUppercased: String? = nil,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil
    ) async throws -> ChatOrchestratorOutput {
        try cancellationToken?.checkCancellation()
        let promptLocalizer = PromptLocalizer()
        let reasoningOpts = buildRuntimeReasoningOptions(inference: inference, model: modelReasoning)
        logger.debug(
            "对话编排开始，history=\(history.count), member=\(shortID(memberID)), inputLength=\(userInput.count), tools=\(inference.useTools), knowledge=\(inference.useKnowledgeBag), web=\(inference.useWebSearch), reasoning=\(reasoningOpts.isEnabled), promptFallback=\(reasoningOpts.usePromptFallback)",
            module: .aiConfig
        )

        let toolResult: ToolHubResult
        if inference.useTools {
            try cancellationToken?.checkCancellation()
            toolResult = await toolHub.runIfNeeded(
                userInput: userInput,
                memberID: memberID,
                allowedToolNames: inference.allowedToolNames
            )
        } else {
            toolResult = .none
        }
        try cancellationToken?.checkCancellation()
        if case .executed(let result) = toolResult {
            let modelConsent = consentGate.evaluate(result: result, destination: .model)
            logger.info(
                "工具调用已命中，tool=\(result.toolName), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive), consentAllowed=\(modelConsent.allowed)",
                module: .aiConfig
            )
            let output = modelConsent.allowed
                ? result.outputText
                : """
                \(result.outputText)

                \(promptLocalizer.consentBlockedHint(reason: modelConsent.reason))
                """
            return ChatOrchestratorOutput(
                text: output,
                reasoningText: nil,
                reasoningDurationMs: nil,
                finishReason: nil,
                kind: .tool,
                toolName: result.toolName,
                toolContent: result.outputText
            )
        }

        // 无工具命中时转入模型推理路径，显式记录入参规模，便于排查上下文膨胀问题。
        let runtimeMessages = await makeRuntimeMessages(
            from: history,
            systemPrompt: systemPrompt,
            memberContextSummary: memberContextSummary,
            reasoning: reasoningOpts,
            deliverMultimodalImages: deliverMultimodalImages,
            maxMessages: maxMessages
        )
        let baseToolDefinitions = filteredToolDefinitions(inference: inference)
        var activeToolDefinitions = baseToolDefinitions
        var activeToolChoice: AIRuntimeToolChoice = inference.useTools && baseToolDefinitions.isEmpty == false ? .auto : .none
        var roundToolLocked = false
        let toolLockedNotice = "本轮对话内已禁止继续调用工具。请基于现有信息直接完成回复，不要再发起工具调用。"
        logger.debug(
            "进入 AI 推理路径，runtimeMessages=\(runtimeMessages.count), memberContextLength=\(memberContextSummary.count), tools=\(baseToolDefinitions.count), toolChoice=\(String(describing: activeToolChoice))",
            module: .aiConfig
        )
        var loopMessages = runtimeMessages
        var loopMemberID = memberID
        let maxToolRounds = 6
        var round = 0
        var executedTools: [ToolExecutionResult] = []

        while round < maxToolRounds {
            round += 1
            try cancellationToken?.checkCancellation()
            let collected: CollectedRuntimeResponse
            do {
                collected = try await collectRuntimeResponse(
                    from: try await runtimeService.generateTextStream(
                        request: AIRuntimeTextRequest(
                            scenario: .chat,
                            messages: loopMessages,
                            tools: activeToolDefinitions,
                            toolChoice: activeToolChoice,
                            reasoning: reasoningOpts,
                            preferredModelName: preferredModelName,
                            providerCompanyUppercased: providerCompanyUppercased,
                            temperature: temperature,
                            topP: topP,
                            maxTokens: maxTokens,
                            cancellationToken: cancellationToken
                        )
                    ),
                    cancellationToken: cancellationToken,
                    onPartial: onPartial
                )
            } catch {
                logger.error("AI 推理路径失败：\(error.localizedDescription)", module: .aiConfig)
                throw error
            }
            let response = collected.response
            let toolTrace = makeToolTrace(from: executedTools)

            if response.hasToolCalls == false {
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    logger.warning("AI 返回空文本，转为可见错误气泡", module: .aiConfig)
                    throw AIRuntimeError.emptyOutput
                }
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    reasoningDurationMs: collected.reasoningDurationMs,
                    finishReason: response.finishReason,
                    kind: .text,
                    toolName: toolTrace?.name,
                    toolContent: toolTrace?.content
                )
            }

            if inference.useTools == false || activeToolDefinitions.isEmpty {
                if response.hasToolCalls {
                    loopMessages.append(AIRuntimeMessage(role: .assistant, content: nil, toolCalls: response.toolCalls))
                    loopMessages.append(AIRuntimeMessage(role: .system, content: toolLockedNotice))
                    continue
                }
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    logger.warning("AI 返回空文本（工具禁用分支），转为可见错误气泡", module: .aiConfig)
                    throw AIRuntimeError.emptyOutput
                }
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    reasoningDurationMs: collected.reasoningDurationMs,
                    finishReason: response.finishReason,
                    kind: .text,
                    toolName: toolTrace?.name,
                    toolContent: toolTrace?.content
                )
            }

            logger.info(
                "模型返回 tool_calls，round=\(round), count=\(response.toolCalls.count)",
                module: .aiConfig
            )
            loopMessages.append(
                AIRuntimeMessage(role: .assistant, content: nil, toolCalls: response.toolCalls)
            )
            for call in response.toolCalls {
                try cancellationToken?.checkCancellation()
                let roundReasoning = response.reasoningText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                await emitToolPartial(
                    answer: "",
                    reasoning: roundReasoning,
                    toolName: call.name,
                    detail: nil,
                    onPartial: onPartial
                )
                let toolResult = await toolHub.executeToolCall(
                    name: call.name,
                    arguments: call.arguments,
                    memberID: loopMemberID,
                    threadID: threadID,
                    assistantMessageClientID: assistantMessageClientID,
                    pendingToolCallID: call.id,
                    pendingResumeMessages: loopMessages
                )
                await emitToolPartial(
                    answer: "",
                    reasoning: roundReasoning,
                    toolName: call.name,
                    detail: toolResult.outputText,
                    onPartial: onPartial
                )
                executedTools.append(toolResult)
                if let resolvedMemberID = toolResult.resolvedMemberID {
                    loopMemberID = resolvedMemberID
                }
                let modelConsent = consentGate.evaluate(result: toolResult, destination: .model)
                let content = modelConsent.allowed
                    ? toolResult.outputText
                    : promptLocalizer.consentBlockedHint(reason: modelConsent.reason)
                loopMessages.append(
                    AIRuntimeMessage(
                        role: .tool,
                        content: content,
                        toolCallID: call.id,
                        name: call.name
                    )
                )
                if toolResult.isAwaitingUserInput {
                    roundToolLocked = true
                    activeToolDefinitions = []
                    activeToolChoice = .none
                    loopMessages.append(AIRuntimeMessage(role: .system, content: toolLockedNotice))
                    break
                }
            }
            if roundToolLocked {
                roundToolLocked = false
                continue
            }
        }

        logger.warning("工具调用超过最大轮次，回退兜底文案", module: .aiConfig)
        return ChatOrchestratorOutput(
            text: promptLocalizer.fallbackAssistantText(),
            reasoningText: nil,
            reasoningDurationMs: nil,
            finishReason: "length",
            kind: .text,
            toolName: nil,
            toolContent: nil
        )
    }

    private func buildRuntimeReasoningOptions(
        inference: ChatOrchestratorInferenceOptions,
        model: ChatModelReasoningContext
    ) -> AIRuntimeReasoningOptions {
        let userWants = inference.reasoningEnabled
        let tier = inference.reasoningEffortTier
        if model.supportsReasoning {
            if model.reasoningControllable {
                return AIRuntimeReasoningOptions(
                    isEnabled: userWants,
                    effortTier: tier,
                    usePromptFallback: false
                )
            }
            return AIRuntimeReasoningOptions(
                isEnabled: true,
                effortTier: tier,
                usePromptFallback: false
            )
        }
        return AIRuntimeReasoningOptions(
            isEnabled: userWants,
            effortTier: tier,
            usePromptFallback: userWants
        )
    }

    private func makeRuntimeMessages(
        from history: [ChatMessage],
        systemPrompt: String?,
        memberContextSummary: String,
        reasoning: AIRuntimeReasoningOptions,
        deliverMultimodalImages: Bool,
        maxMessages: Int?
    ) async -> [AIRuntimeMessage] {
        let promptLocalizer = PromptLocalizer()
        var systemBlocks = [
            (systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? promptLocalizer.chatSystemPrompt()
        ]

        if memberContextSummary.isEmpty == false {
            systemBlocks.append(memberContextSummary)
        }

        if reasoning.usePromptFallback {
            systemBlocks.append(promptLocalizer.deepThinkingInstruction())
        }

        var runtimeMessages: [AIRuntimeMessage] = [
            AIRuntimeMessage(role: .system, content: systemBlocks.joined(separator: "\n\n"))
        ]

        let effectiveHistory: ArraySlice<ChatMessage>
        if let maxMessages, maxMessages > 0 {
            effectiveHistory = history.suffix(maxMessages)
        } else {
            effectiveHistory = history[history.startIndex..<history.endIndex]
        }

        for chatMessage in effectiveHistory where chatMessage.role != .system {
            let msg = await runtimeMessage(from: chatMessage, deliverMultimodalImages: deliverMultimodalImages)
            runtimeMessages.append(msg)
        }
        return runtimeMessages
    }

    private func runtimeMessage(from message: ChatMessage, deliverMultimodalImages: Bool) async -> AIRuntimeMessage {
        // 多模态模式：从本地缓存读取 JPEG 字节并内联 base64（不向模型发送远端 URL）
        if deliverMultimodalImages, message.role == .user {
            if let parts = await buildMultimodalParts(from: message) {
                return AIRuntimeMessage(role: .user, content: nil, contentParts: parts)
            }
        }

        // LocalOCR 模式：非多模态但有图片附件时，从附件中提取 OCR 文本拼接
        if message.role == .user, message.attachments.isEmpty == false {
            let enhancedContent = buildLocalOCRContent(from: message)
            if enhancedContent != message.content {
                return AIRuntimeMessage(role: .user, content: enhancedContent)
            }
        }

        return AIRuntimeMessage(role: message.role.runtimeRole, content: message.content)
    }

    private func buildMultimodalParts(from message: ChatMessage) async -> [AIRuntimeContentPart]? {
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageAttachments = message.attachments.filter { $0.isUserImageForMultimodal }
        guard imageAttachments.isEmpty == false else { return nil }
        var parts: [AIRuntimeContentPart] = []
        if text.isEmpty == false {
            parts.append(.textPart(text))
        } else {
            parts.append(.textPart(" "))
        }
        for att in imageAttachments {
            let jpegData: Data?
            if let parsed = att.sparkClientOSSFileUUIDAndFileName(),
               let localURL = await fileCacheManager.cachedFileURL(fileUUID: parsed.fileUUID, fileName: parsed.fileName),
               let data = try? Data(contentsOf: localURL),
               let converted = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                jpegData = converted
            } else if let url = att.url,
                      let data = try? await URLSession.shared.data(from: url).0,
                      let converted = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                jpegData = converted
            } else {
                jpegData = nil
            }
            guard let jpegData else {
                logger.debug("多模态：无法取得图片字节（缓存或 URL），跳过", module: .aiConfig)
                return nil
            }
            parts.append(.imageInlineJPEGBase64(jpegData.base64EncodedString()))
        }
        return parts.count > 1 ? parts : nil
    }

    /// LocalOCR 模式：从附件元数据中提取 OCR 文本，构造增强后的用户内容
    private func buildLocalOCRContent(from message: ChatMessage) -> String {
        let userText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = message.attachments.filter { $0.isUserFileForLocalOCR }
        guard attachments.isEmpty == false else { return message.content }

        var blocks: [String] = []
        for attachment in attachments {
            let ocr = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fileIdStr = "file_id=\(attachment.fileId.map(String.init) ?? "-")"
            let uuidHint = attachment.sparkClientOSSFileUUIDAndFileName()?.fileUUID ?? "-"
            let fileUUIDStr = "file_uuid=\(uuidHint)"
            let label: String = switch attachment.type {
            case .pdf:
                "PDF附件"
            case .file:
                "文件附件"
            default:
                "图片附件"
            }
            let ocrLabel: String = switch attachment.type {
            case .pdf:
                "PDF识别"
            case .file:
                "文件识别"
            default:
                "图片识别"
            }
            blocks.append(
                """
                【\(label)】\(fileIdStr) \(fileUUIDStr)
                【\(ocrLabel)】
                \(ocr.isEmpty ? "(无文字)" : ocr)
                """
            )
        }
        
        if userText.isEmpty == false {
            blocks.append("【用户输入】\n\(userText)")
        }
        
        return blocks.isEmpty ? message.content : blocks.joined(separator: "\n\n")
    }

    private func filteredToolDefinitions(inference: ChatOrchestratorInferenceOptions) -> [AIRuntimeToolDefinition] {
        guard inference.useTools else { return [] }
        var definitions = toolHub.toolDefinitions()
        if inference.useKnowledgeBag == false {
            definitions.removeAll {
                $0.name == SparkToolName.searchKnowledgeBag.rawValue || $0.name == SparkToolName.createKnowledgeDocument.rawValue
            }
        }
        if inference.useWebSearch == false {
            let web: Set<String> = [
                SparkToolName.searchOnline.rawValue,
                SparkToolName.readWebPage.rawValue,
                SparkToolName.searchArxivPapers.rawValue,
                SparkToolName.extractRemoteFileContent.rawValue
            ]
            definitions.removeAll { web.contains($0.name) }
        }
        if let allowed = inference.allowedToolNames {
            let normalizedAllowed = Set(allowed.map(Self.normalizeToolName))
            definitions.removeAll { normalizedAllowed.contains(Self.normalizeToolName($0.name)) == false }
        }
        return definitions
    }

    private static func normalizeToolName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func collectRuntimeResponse(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        cancellationToken: AIRuntimeCancellationToken?,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)?
    ) async throws -> CollectedRuntimeResponse {
        var bufferedText = ""
        var bufferedReasoning = ""
        var toolCallsByIndex: [Int: AIRuntimeToolCall] = [:]
        var completedResponse: AIRuntimeTextResponse?
        var firstReasoningAt: Date?
        var lastReasoningAt: Date?

        for try await event in stream {
            try cancellationToken?.checkCancellation()
            switch event {
            case .textDelta(let delta):
                bufferedText.append(delta)
                if let onPartial {
                    let reasoning = bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                    await onPartial(
                        ChatAssistantPartialDelta(
                            answer: bufferedText,
                            reasoning: reasoning.isEmpty ? nil : reasoning,
                            kind: .text,
                            toolName: nil,
                            toolContent: nil
                        )
                    )
                }
            case .reasoningDelta(let delta):
                let now = Date()
                if firstReasoningAt == nil { firstReasoningAt = now }
                lastReasoningAt = now
                bufferedReasoning.append(delta)
                if let onPartial {
                    let reasoning = bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                    await onPartial(
                        ChatAssistantPartialDelta(
                            answer: bufferedText,
                            reasoning: reasoning.isEmpty ? nil : reasoning,
                            kind: .text,
                            toolName: nil,
                            toolContent: nil
                        )
                    )
                }
            case .toolCallDelta(let delta):
                var call = toolCallsByIndex[delta.index] ?? AIRuntimeToolCall(
                    id: delta.id ?? UUID().uuidString,
                    name: delta.name ?? "",
                    arguments: ""
                )
                if let id = delta.id, id.isEmpty == false {
                    call = AIRuntimeToolCall(id: id, name: call.name, arguments: call.arguments)
                }
                if let name = delta.name, name.isEmpty == false {
                    call = AIRuntimeToolCall(id: call.id, name: name, arguments: call.arguments)
                }
                if let argumentsDelta = delta.argumentsDelta, argumentsDelta.isEmpty == false {
                    call = AIRuntimeToolCall(id: call.id, name: call.name, arguments: call.arguments + argumentsDelta)
                }
                toolCallsByIndex[delta.index] = call
                await emitToolPartial(
                    answer: bufferedText,
                    reasoning: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    toolName: call.name,
                    detail: call.arguments.isEmpty ? nil : call.arguments,
                    onPartial: onPartial
                )
            case .completed(let response):
                completedResponse = response
            }
        }
        let reasoningDurationMs = reasoningDurationMs(
            firstReasoningAt: firstReasoningAt,
            lastReasoningAt: lastReasoningAt
        )

        if let completedResponse {
            return CollectedRuntimeResponse(
                response: completedResponse,
                reasoningDurationMs: reasoningDurationMs
            )
        }

        let reasoningText = bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = AIRuntimeTextResponse(
                text: bufferedText,
                reasoningText: reasoningText.isEmpty ? nil : reasoningText,
                model: "unknown",
                promptTokens: nil,
                completionTokens: nil,
                toolCalls: toolCallsByIndex.keys.sorted().compactMap { toolCallsByIndex[$0] },
                finishReason: nil
            )
        return CollectedRuntimeResponse(
            response: response,
            reasoningDurationMs: reasoningDurationMs
        )
    }

    private struct CollectedRuntimeResponse: Sendable {
        let response: AIRuntimeTextResponse
        let reasoningDurationMs: Int64?
    }

    private func reasoningDurationMs(
        firstReasoningAt: Date?,
        lastReasoningAt: Date?
    ) -> Int64? {
        guard let firstReasoningAt, let lastReasoningAt else { return nil }
        let ms = max(1, Int64(lastReasoningAt.timeIntervalSince(firstReasoningAt) * 1_000))
        return ms
    }

    private func makeToolTrace(from results: [ToolExecutionResult]) -> (name: String, content: String)? {
        guard results.isEmpty == false else { return nil }
        let names = Array(Set(results.map(\.toolName)))
            .map(localizedToolDisplayName(for:))
            .sorted()
            .joined(separator: ", ")
        let content = results.enumerated().map { index, item in
            """
            [\(index + 1)] \(localizedToolDisplayName(for: item.toolName))
            \(item.outputText)
            """
        }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else { return nil }
        return (names, content)
    }

    private func emitToolPartial(
        answer: String,
        reasoning: String?,
        toolName: String,
        detail: String?,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)?
    ) async {
        guard let onPartial else { return }
        await onPartial(
            ChatAssistantPartialDelta(
                answer: answer,
                reasoning: reasoning,
                kind: .tool,
                toolName: toolName.isEmpty ? nil : toolName,
                toolContent: localizedToolOperationText(toolName: toolName, detail: detail)
            )
        )
    }

    private func localizedToolOperationText(toolName: String, detail: String?) -> String {
        let prefix = L10n.text("chat.bubble.tool.operating_prefix", fallback: "Using tool: ")
        let title = localizedToolDisplayName(for: toolName)
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              detail.isEmpty == false else {
            return "\(prefix)\(title)"
        }
        return "\(prefix)\(title)\n\(detail)"
    }

    private func localizedToolDisplayName(for toolName: String) -> String {
        let normalized = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return L10n.text("chat.bubble.tool.default_name", fallback: "Tool")
        }
        let localized = SparkToolName.displayName(for: normalized)
        let fallbackKey = "ai_settings.tools.\(normalized)"
        if localized == fallbackKey {
            return normalized
        }
        return localized
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
