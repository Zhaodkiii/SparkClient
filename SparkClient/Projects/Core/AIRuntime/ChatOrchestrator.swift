import Foundation
import UIKit

struct ChatOrchestratorOutput: Sendable {
    let text: String
    let reasoningText: String?
    let reasoningDurationMs: Int64?
    let kind: ChatMessageKind
    let toolName: String?
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
        preferredModelName: String? = nil,
        /// 为 `true` 时，用户消息中的 `image_url` 附件编码为多模态 `content` 数组；否则仅使用 `ChatMessage.content` 字符串。
        deliverMultimodalImages: Bool = false,
        /// 网关单点编码（如厂商对 `image_url` 形式的差异）。
        providerCompanyUppercased: String? = nil,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil
    ) async throws -> ChatOrchestratorOutput {
        let promptLocalizer = PromptLocalizer()
        let reasoningOpts = buildRuntimeReasoningOptions(inference: inference, model: modelReasoning)
        logger.debug(
            "对话编排开始，history=\(history.count), member=\(shortID(memberID)), inputLength=\(userInput.count), tools=\(inference.useTools), knowledge=\(inference.useKnowledgeBag), web=\(inference.useWebSearch), reasoning=\(reasoningOpts.isEnabled), promptFallback=\(reasoningOpts.usePromptFallback)",
            module: .aiConfig
        )

        let toolResult: ToolHubResult
        if inference.useTools {
            toolResult = await toolHub.runIfNeeded(userInput: userInput, memberID: memberID)
        } else {
            toolResult = .none
        }
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
                kind: .tool,
                toolName: result.toolName,
                toolContent: result.outputText
            )
        }

        // 无工具命中时转入模型推理路径，显式记录入参规模，便于排查上下文膨胀问题。
        let runtimeMessages = await makeRuntimeMessages(
            from: history,
            memberContextSummary: memberContextSummary,
            reasoning: reasoningOpts,
            deliverMultimodalImages: deliverMultimodalImages
        )
        let toolDefinitions = filteredToolDefinitions(inference: inference)
        let toolChoice: AIRuntimeToolChoice = inference.useTools && toolDefinitions.isEmpty == false ? .auto : .none
        logger.debug(
            "进入 AI 推理路径，runtimeMessages=\(runtimeMessages.count), memberContextLength=\(memberContextSummary.count), tools=\(toolDefinitions.count), toolChoice=\(String(describing: toolChoice))",
            module: .aiConfig
        )
        var loopMessages = runtimeMessages
        let maxToolRounds = 3
        var round = 0
        var executedTools: [ToolExecutionResult] = []

        while round < maxToolRounds {
            round += 1
            let collected: CollectedRuntimeResponse
            do {
                collected = try await collectRuntimeResponse(
                    from: try await runtimeService.generateTextStream(
                        request: AIRuntimeTextRequest(
                            scenario: .chat,
                            messages: loopMessages,
                            tools: toolDefinitions,
                            toolChoice: toolChoice,
                            reasoning: reasoningOpts,
                            preferredModelName: preferredModelName,
                            providerCompanyUppercased: providerCompanyUppercased
                        )
                    ),
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
                    logger.warning("AI 返回空文本，已回退到默认兜底文案", module: .aiConfig)
                }
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text.isEmpty ? promptLocalizer.fallbackAssistantText() : text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    reasoningDurationMs: collected.reasoningDurationMs,
                    kind: .text,
                    toolName: toolTrace?.name,
                    toolContent: toolTrace?.content
                )
            }

            if inference.useTools == false || toolDefinitions.isEmpty {
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatOrchestratorOutput(
                    text: text.isEmpty ? promptLocalizer.fallbackAssistantText() : text,
                    reasoningText: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                    reasoningDurationMs: collected.reasoningDurationMs,
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
                let roundReasoning = response.reasoningText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let toolStartText = "使用工具：\(call.name)"
                if let onPartial {
                    await onPartial(
                        ChatAssistantPartialDelta(
                            answer: "",
                            reasoning: roundReasoning,
                            kind: .tool,
                            toolName: call.name,
                            toolContent: toolStartText
                        )
                    )
                }
                let toolResult = await toolHub.executeToolCall(
                    name: call.name,
                    arguments: call.arguments,
                    memberID: memberID,
                    threadID: threadID,
                    assistantMessageClientID: assistantMessageClientID
                )
                let toolFinishText = "使用工具：\(call.name)\n\(toolResult.outputText)"
                if let onPartial {
                    await onPartial(
                        ChatAssistantPartialDelta(
                            answer: "",
                            reasoning: roundReasoning,
                            kind: .tool,
                            toolName: call.name,
                            toolContent: toolFinishText
                        )
                    )
                }
                executedTools.append(toolResult)
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
            }
        }

        logger.warning("工具调用超过最大轮次，回退兜底文案", module: .aiConfig)
        return ChatOrchestratorOutput(
            text: promptLocalizer.fallbackAssistantText(),
            reasoningText: nil,
            reasoningDurationMs: nil,
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
        memberContextSummary: String,
        reasoning: AIRuntimeReasoningOptions,
        deliverMultimodalImages: Bool
    ) async -> [AIRuntimeMessage] {
        let promptLocalizer = PromptLocalizer()
        var runtimeMessages: [AIRuntimeMessage] = [
            AIRuntimeMessage(role: .system, content: promptLocalizer.chatSystemPrompt())
        ]

        if memberContextSummary.isEmpty == false {
            runtimeMessages.append(
                AIRuntimeMessage(role: .system, content: memberContextSummary)
            )
        }

        if reasoning.usePromptFallback {
            runtimeMessages.append(
                AIRuntimeMessage(role: .system, content: promptLocalizer.deepThinkingInstruction())
            )
        }

        for chatMessage in history {
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
                $0.name == SparkToolName.searchKnowledgeBag || $0.name == SparkToolName.createKnowledgeDocument
            }
        }
        if inference.useWebSearch == false {
            let web: Set<String> = [
                SparkToolName.searchOnline,
                SparkToolName.readWebPage,
                SparkToolName.searchArxivPapers,
                SparkToolName.extractRemoteFileContent
            ]
            definitions.removeAll { web.contains($0.name) }
        }
        return definitions
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func collectRuntimeResponse(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)?
    ) async throws -> CollectedRuntimeResponse {
        var bufferedText = ""
        var bufferedReasoning = ""
        var toolCallsByIndex: [Int: AIRuntimeToolCall] = [:]
        var completedResponse: AIRuntimeTextResponse?
        var firstReasoningAt: Date?
        var lastReasoningAt: Date?

        for try await event in stream {
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
                if let onPartial {
                    let content: String
                    if call.arguments.isEmpty {
                        content = "使用工具：\(call.name.isEmpty ? "Tool" : call.name)"
                    } else {
                        content = "使用工具：\(call.name.isEmpty ? "Tool" : call.name)\n\(call.arguments)"
                    }
                    await onPartial(
                        ChatAssistantPartialDelta(
                            answer: bufferedText,
                            reasoning: bufferedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                            kind: .tool,
                            toolName: call.name.isEmpty ? nil : call.name,
                            toolContent: content
                        )
                    )
                }
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
            .sorted()
            .joined(separator: ", ")
        let content = results.enumerated().map { index, item in
            """
            [\(index + 1)] \(item.toolName)
            \(item.outputText)
            """
        }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else { return nil }
        return (names, content)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
