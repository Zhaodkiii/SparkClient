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
    let blocks: [ChatMessageBlock]
}
/// 助手流式回调的标准增量模型。
/// 统一承载“正文 / 推理 / 工具链路”字段，避免多参数回调扩散。
struct ChatAssistantPartialDelta: Sendable {
    let answer: String
    let reasoning: String?
    let kind: ChatMessageKind
    let toolName: String?
    let toolContent: String?
    let toolCallID: String?
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

    /// AI 核心：生成回复（支持流式输出、工具调用、多轮循环、多模态）
    func generateReply(
        userInput: String,                                   // 用户输入文本
        history: [ChatMessage],                              // 聊天历史
        memberContextSummary: String,                        // 成员上下文摘要
        memberID: Int?,                                      // 成员ID
        threadID: UUID? = nil,                                // 对话ID
        assistantMessageClientID: UUID? = nil,               // 助手消息ID
        inference: ChatOrchestratorInferenceOptions = .default, // 推理选项
        modelReasoning: ChatModelReasoningContext = .unknown,   // 模型推理配置
        systemPrompt: String? = nil,                         // 系统提示词
        preferredModelName: String? = nil,                    // 优先使用的模型
        temperature: Double? = nil,                           // 温度系数（随机性）
        topP: Double? = nil,                                  // 核采样参数
        maxTokens: Int? = nil,                                // 最大token
        maxMessages: Int? = nil,                              // 最大消息数
        cancellationToken: AIRuntimeCancellationToken? = nil, // 取消令牌
        deliverMultimodalImages: Bool = false,                // 是否发送多模态图片
        providerCompanyUppercased: String? = nil,              // 模型厂商
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil // 流式回调
    ) async throws -> ChatOrchestratorOutput {
        // 检查是否取消请求
        try cancellationToken?.checkCancellation()
        let promptLocalizer = PromptLocalizer()
        // 构建推理配置（是否开启深度思考、提示词回退等）
        let reasoningOpts = buildRuntimeReasoningOptions(inference: inference, model: modelReasoning)
        
        logger.debug(
            "对话编排开始，history=\(history.count), member=\(shortID(memberID)), inputLength=\(userInput.count), tools=\(inference.useTools), knowledge=\(inference.useKnowledgeBag), web=\(inference.useWebSearch), reasoning=\(reasoningOpts.isEnabled), promptFallback=\(reasoningOpts.usePromptFallback)",
            module: .aiConfig
        )

        // MARK: - 第一步：判断是否需要调用工具（如联网搜索、文件、插件等）
        let toolResult: ToolHubResult
        if inference.useTools {
            try cancellationToken?.checkCancellation()
            // 工具中心判断是否需要执行工具
            toolResult = await toolHub.runIfNeeded(
                userInput: userInput,
                memberID: memberID,
                allowedToolNames: inference.allowedToolNames,
                threadID: threadID
            )
        } else {
            toolResult = .none
        }

        try cancellationToken?.checkCancellation()
        
        // MARK: - 工具已直接执行完成（无需走AI模型），直接返回结果
        if case .executed(let result) = toolResult {
            let modelConsent = await consentGate.awaitModelConsent(
                result: result,
                callArguments: "",
                providerCompany: providerCompanyUppercased,
                modelName: preferredModelName,
                endpoint: nil,
                privacyPolicyURL: nil,
                threadID: threadID
            )
            logger.info(
                "工具调用已命中，tool=\(result.toolName), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive), consentAllowed=\(modelConsent.allowed)",
                module: .aiConfig
            )
            
            // 权限校验：允许则返回原文，否则返回拦截提示
            let output = modelConsent.allowed
                ? result.outputText
                : """
                \(result.outputText)

                \(promptLocalizer.consentBlockedHint(reason: modelConsent.reason))
                """
            
            // 返回工具类结果
            return ChatOrchestratorOutput(
                text: output,
                reasoningText: nil,
                reasoningDurationMs: nil,
                finishReason: nil,
                kind: .tool,
                toolName: result.toolName,
                toolContent: result.outputText,
                blocks: [
                    ChatMessageBlock(
                        kind: .tool,
                        text: result.outputText,
                        toolName: result.toolName
                    )
                ]
            )
        }

        // MARK: - 无工具直接命中 → 进入AI模型推理流程
        // 构建给AI模型的消息上下文（历史+系统提示+用户上下文）
        let runtimeMessages = await makeRuntimeMessages(
            from: history,
            systemPrompt: systemPrompt,
            memberContextSummary: memberContextSummary,
            reasoning: reasoningOpts,
            deliverMultimodalImages: deliverMultimodalImages,
            maxMessages: maxMessages
        )
        
        // 获取可用工具列表
        let baseToolDefinitions = filteredToolDefinitions(inference: inference)
        var activeToolDefinitions = baseToolDefinitions
        var activeToolChoice: AIRuntimeToolChoice = inference.useTools && baseToolDefinitions.isEmpty == false ? .auto : .none
        var roundToolLocked = false // 工具锁定标记
        let toolCallLoopStrategy = RuntimeToolCallLoopStrategy(
            providerCompanyUppercased: providerCompanyUppercased,
            preferredModelName: preferredModelName,
            reasoning: reasoningOpts
        )
        let toolLockedNotice = "本轮对话内已禁止继续调用工具。请基于现有信息直接完成回复，不要再发起工具调用。"
        
        logger.debug(
            "进入 AI 推理路径，runtimeMessages=\(runtimeMessages.count), memberContextLength=\(memberContextSummary.count), tools=\(baseToolDefinitions.count), toolChoice=\(String(describing: activeToolChoice))",
            module: .aiConfig
        )

        // 循环用变量
        var loopMessages = runtimeMessages
        var loopMemberID = memberID
        let maxToolRounds = 30 // 最大工具调用轮次
        var round = 0
        var executedTools: [ToolExecutionResult] = []

        // MARK: - AI + 工具 多轮循环（最多30轮）
        while round < maxToolRounds {
            round += 1
            try cancellationToken?.checkCancellation()
            
            let collected: CollectedRuntimeResponse
            do {
                // MARK: 核心：调用AI模型流式生成
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

            // MARK: - AI 不调用工具 → 直接返回文本结果
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
                    toolContent: toolTrace?.content,
                    blocks: buildOutputBlocks(
                        text: text,
                        reasoning: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                        toolName: toolTrace?.name,
                        toolContent: toolTrace?.content,
                        executedTools: executedTools
                    )
                )
            }

            // MARK: - 禁用工具但AI仍想调用 → 强制禁止并继续
            if inference.useTools == false || activeToolDefinitions.isEmpty {
                if response.hasToolCalls {
                    let assistantReasoning = response.reasoningText?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nilIfEmpty
                    loopMessages.append(
                        AIRuntimeMessage(
                            role: .assistant,
                            content: nil,
                            toolCalls: response.toolCalls,
                            reasoningContent: toolCallLoopStrategy.reasoningContentForAssistantToolMessage(
                                assistantReasoning,
                                toolCalls: response.toolCalls
                            )
                        )
                    )
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
                    toolContent: toolTrace?.content,
                    blocks: buildOutputBlocks(
                        text: text,
                        reasoning: reasoning.flatMap { $0.isEmpty ? nil : $0 },
                        toolName: toolTrace?.name,
                        toolContent: toolTrace?.content,
                        executedTools: executedTools
                    )
                )
            }

            // MARK: - AI 决定调用工具 → 执行工具并追加结果
            logger.info(
                "模型返回 tool_calls，round=\(round), count=\(response.toolCalls.count)",
                module: .aiConfig
            )
            
            let roundAnswer = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let roundReasoning = response.reasoningText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let toolCallsToExecute = response.toolCalls
            guard toolCallsToExecute.isEmpty == false else {
                continue
            }
            // 同一 assistant 消息里的 tool_calls 必须全部执行并逐个回灌 tool result，避免模型上下文状态断裂。
            loopMessages.append(
                AIRuntimeMessage(
                    role: .assistant,
                    content: roundAnswer.isEmpty ? nil : roundAnswer,
                    toolCalls: toolCallsToExecute,
                    reasoningContent: toolCallLoopStrategy.reasoningContentForAssistantToolMessage(
                        roundReasoning,
                        toolCalls: toolCallsToExecute
                    )
                )
            )
            try cancellationToken?.checkCancellation()

            for call in toolCallsToExecute {
                try cancellationToken?.checkCancellation()
                
                // 前端UI：显示工具调用中
                await emitToolPartial(
                    answer: roundAnswer,
                    reasoning: roundReasoning,
                    toolName: call.name,
                    toolCallID: call.id,
                    detail: nil,
                    onPartial: onPartial
                )

                // MARK: 执行工具
                let toolResult = await toolHub.executeToolCall(
                    name: call.name,
                    arguments: call.arguments,
                    memberID: loopMemberID,
                    threadID: threadID,
                    assistantMessageClientID: assistantMessageClientID,
                    pendingToolCallID: call.id,
                    pendingResumeMessages: loopMessages
                )

                // 工具执行完成 → 前端显示结果
                await emitToolPartial(
                    answer: roundAnswer,
                    reasoning: roundReasoning,
                    toolName: call.name,
                    toolCallID: call.id,
                    detail: toolResult.outputText,
                    onPartial: onPartial
                )

                // 记录已执行工具
                executedTools.append(toolResult)
                
                // 成员ID可能被工具更新
                if let resolvedMemberID = toolResult.resolvedMemberID {
                    loopMemberID = resolvedMemberID
                }

                // 权限校验
                let modelConsent = await consentGate.awaitModelConsent(
                    result: toolResult,
                    callArguments: call.arguments,
                    providerCompany: providerCompanyUppercased,
                    modelName: preferredModelName,
                    endpoint: nil,
                    privacyPolicyURL: nil,
                    threadID: threadID
                )
                let content = modelConsent.allowed
                    ? toolResult.outputText
                    : promptLocalizer.consentBlockedHint(reason: modelConsent.reason)
                
                // 把工具返回结果加入消息上下文
                loopMessages.append(
                    AIRuntimeMessage(
                        role: .tool,
                        content: content,
                        toolCallID: call.id,
                        name: call.name
                    )
                )

                // 如果工具需要用户输入 → 锁定工具，禁止继续调用
                if toolResult.isAwaitingUserInput {
                    roundToolLocked = true
                    activeToolDefinitions = []
                    activeToolChoice = .none
                    loopMessages.append(AIRuntimeMessage(role: .system, content: toolLockedNotice))
                    break
                }
            }

            // 解锁工具锁定，继续下一轮循环
            if roundToolLocked {
                roundToolLocked = false
                continue
            }
        }

        // MARK: - 超过最大工具轮次 → 返回兜底文案
        logger.warning("工具调用超过最大轮次，回退兜底文案", module: .aiConfig)
        return ChatOrchestratorOutput(
            text: promptLocalizer.fallbackAssistantText(),
            reasoningText: nil,
            reasoningDurationMs: nil,
            finishReason: "length",
            kind: .text,
            toolName: nil,
            toolContent: nil,
            blocks: [ChatMessageBlock(kind: .text, text: promptLocalizer.fallbackAssistantText())]
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
        let messageText = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let messageAttachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)

        // 多模态模式：从本地缓存读取 JPEG 字节并内联 base64（不向模型发送远端 URL）
        if deliverMultimodalImages, message.role == .user {
            if let parts = await buildMultimodalParts(from: message) {
                return AIRuntimeMessage(role: .user, content: nil, contentParts: parts)
            }
        }

        // LocalOCR 模式：非多模态但有图片附件时，从附件中提取 OCR 文本拼接
        if message.role == .user, messageAttachments.isEmpty == false {
            let enhancedContent = buildLocalOCRContent(from: message)
            if enhancedContent != messageText {
                return AIRuntimeMessage(role: .user, content: enhancedContent)
            }
        }

        return AIRuntimeMessage(role: message.role.runtimeRole, content: messageText)
    }

    private func buildMultimodalParts(from message: ChatMessage) async -> [AIRuntimeContentPart]? {
        let text = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imageAttachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
            .filter { $0.isUserImageForMultimodal }
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
        let userText = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
            .filter { $0.isUserFileForLocalOCR }
        guard attachments.isEmpty == false else { return userText }

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
        
        return blocks.isEmpty ? userText : blocks.joined(separator: "\n\n")
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
                            toolContent: nil,
                            toolCallID: nil
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
                            toolContent: nil,
                            toolCallID: nil
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
                    toolCallID: call.id,
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
        toolCallID: String?,
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
                toolContent: localizedToolOperationText(toolName: toolName, detail: detail),
                toolCallID: toolCallID
            )
        )
    }

    private func buildOutputBlocks(
        text: String,
        reasoning: String?,
        toolName: String?,
        toolContent: String?,
        executedTools: [ToolExecutionResult]
    ) -> [ChatMessageBlock] {
        let blocks: [ChatMessageBlock] = []
//        if let reasoning, reasoning.isEmpty == false {
//            blocks.append(ChatMessageBlock(kind: .reasoning, text: reasoning))
//        }
//        if executedTools.isEmpty == false {
//            for result in executedTools {
//                blocks.append(
//                    ChatMessageBlock(
//                        kind: .tool,
//                        text: result.outputText,
//                        toolName: result.toolName
//                    )
//                )
//            }
//        } else if let toolContent, toolContent.isEmpty == false {
//            blocks.append(ChatMessageBlock(kind: .tool, text: toolContent, toolName: toolName))
//        }
//        if text.isEmpty == false {
//            blocks.append(ChatMessageBlock(kind: .text, text: text))
//        }
        return blocks
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

/// 模型工具循环策略。
/// 所有模型的同一子轮 tool_calls 都完整执行；DeepSeek 思考工具调用额外遵循官方规则，
/// 在 assistant tool_calls 消息中回传 `reasoning_content`。
private struct RuntimeToolCallLoopStrategy {
    enum Mode {
        case openAICompatible
        case deepSeekThinking
    }

    let mode: Mode
    let reasoning: AIRuntimeReasoningOptions

    init(
        providerCompanyUppercased: String?,
        preferredModelName: String?,
        reasoning: AIRuntimeReasoningOptions
    ) {
        self.reasoning = reasoning
        if Self.isDeepSeek(providerCompanyUppercased: providerCompanyUppercased, modelName: preferredModelName),
           reasoning.isEnabled,
           reasoning.usePromptFallback == false {
            mode = .deepSeekThinking
        } else {
            mode = .openAICompatible
        }
    }

    func reasoningContentForAssistantToolMessage(
        _ reasoningContent: String?,
        toolCalls: [AIRuntimeToolCall]
    ) -> String? {
        guard toolCalls.isEmpty == false,
              let reasoningContent,
              reasoningContent.isEmpty == false
        else {
            return nil
        }
        switch mode {
        case .openAICompatible:
            return nil
        case .deepSeekThinking:
            return reasoningContent
        }
    }

    private static func isDeepSeek(providerCompanyUppercased: String?, modelName: String?) -> Bool {
        if providerCompanyUppercased?.uppercased().contains("DEEPSEEK") == true {
            return true
        }
        return modelName?.lowercased().contains("deepseek") == true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
