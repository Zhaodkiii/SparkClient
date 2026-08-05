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
    let toolArguments: String?
    /// 工具执行结果或 ToolHub 解析后的参数字典，供工具详情 Sheet 展示。
    let toolInvocationArguments: [String: String]?
    let toolCallID: String?
}

struct ChatOrchestrator: Sendable {
    let runtimeService: any AIRuntimeServing
    let toolHub: ToolHub
    let fileCacheManager: FileCacheManager
    let logger: Logger

    init(
        runtimeService: any AIRuntimeServing,
        toolHub: ToolHub,
        fileCacheManager: FileCacheManager,
        logger: Logger = ConsoleLogger()
    ) {
        self.runtimeService = runtimeService
        self.toolHub = toolHub
        self.fileCacheManager = fileCacheManager
        self.logger = logger
    }

    /// AI 核心：生成回复（支持流式输出、工具调用、多轮循环、多模态）
    func generateReply(
        userInput: String,                                   // 用户输入文本
        healthResourceContext: String? = nil,                // 问报告：健康资料上下文（单独 user 消息）
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
        sendsOriginalImagesToAI: Bool = false,                 // 多模态图片是否使用原图
        providerCompanyUppercased: String? = nil,              // 模型厂商
        onPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil, // 流式回调
        messageRunActor: MessageRunActor? = nil               // 工具 UI 副作用串行落库
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
            logger.info(
                "工具调用已命中，tool=\(result.toolName), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive)",
                module: .aiConfig
            )

            if let messageRunActor, let assistantID = assistantMessageClientID {
                for effect in result.sideEffects {
                    await messageRunActor.apply(
                        .toolSideEffect(
                            effect,
                            anchorToolCallID: nil,
                            assistantClientMessageID: assistantID
                        )
                    )
                }
            }

            // 返回工具类结果
            return ChatOrchestratorOutput(
                text: result.outputText,
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
        let buildResult = await makeRuntimeMessages(
            from: history,
            systemPrompt: systemPrompt,
            memberContextSummary: memberContextSummary,
            reasoning: reasoningOpts,
            deliverMultimodalImages: deliverMultimodalImages,
            sendsOriginalImagesToAI: sendsOriginalImagesToAI,
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
            "进入 AI 推理路径，runtimeMessages=\(buildResult.messages.count), memberContextLength=\(memberContextSummary.count), tools=\(baseToolDefinitions.count), toolChoice=\(String(describing: activeToolChoice))",
            module: .aiConfig
        )

        var loopMessages = Self.applyOutboundUserTurn(
            userInput: userInput,
            healthResourceContext: healthResourceContext,
            buildResult: buildResult
        )
        logOutboundUserTurnMerge(
            buildResult: buildResult,
            loopMessages: loopMessages,
            healthResourceContext: healthResourceContext
        )
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
                
                // 前端UI：显示工具调用中（带上模型传入参数，避免覆盖流式阶段已展示的 arguments）
                await emitToolPartial(
                    answer: roundAnswer,
                    reasoning: roundReasoning,
                    toolName: call.name,
                    toolCallID: call.id,
                    toolArguments: trimmedToolCallArguments(call.arguments),
                    detail: trimmedToolCallArguments(call.arguments),
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
                    pendingResumeMessages: loopMessages,
                    providerCompany: providerCompanyUppercased,
                    modelName: preferredModelName,
                    endpoint: nil,
                    privacyPolicyURL: nil
                )

                // 工具执行完成 → 前端显示「参数 + 输出」，供气泡与工具详情 Sheet 共用
                await emitToolPartial(
                    answer: roundAnswer,
                    reasoning: roundReasoning,
                    toolName: call.name,
                    toolCallID: call.id,
                    toolArguments: trimmedToolCallArguments(call.arguments),
                    toolInvocationArguments: resolvedToolInvocationArguments(
                        toolResult: toolResult,
                        callArguments: call.arguments
                    ),
                    detail: toolCallDetail(arguments: call.arguments, output: toolResult.outputText),
                    onPartial: onPartial
                )

                if let messageRunActor, let assistantID = assistantMessageClientID {
                    let anchor = toolResult.anchorToolCallID ?? call.id
                    for effect in toolResult.sideEffects {
                        await messageRunActor.apply(
                            .toolSideEffect(
                                effect,
                                anchorToolCallID: anchor,
                                assistantClientMessageID: assistantID
                            )
                        )
                    }
                }

                // 记录已执行工具
                executedTools.append(toolResult)
                
                // 成员ID可能被工具更新
                if let resolvedMemberID = toolResult.resolvedMemberID {
                    loopMemberID = resolvedMemberID
                }

                // 把工具返回结果加入消息上下文
                loopMessages.append(
                    AIRuntimeMessage(
                        role: .tool,
                        content: toolResult.outputText,
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

    /// 将本轮出站上下文合并进发给模型的 `messages`（不修改本地历史的 block 结构）。
    ///
    /// - `userInput`：本轮纯文本问题（`SendChatMessageUseCase` 传入，不等于最终 provider body）。
    /// - `healthResourceContext`：问报告等场景的健康资料前缀，可为空。
    /// - `buildResult`：`makeRuntimeMessages` 产物，含最后一条 user 的组包来源标记。
    ///
    /// 合并策略按 `LastUserTurnSource` 分支，避免用纯文本覆盖 LocalOCR 已拼好的 `【图片识别】` 等内容。
    private static func applyOutboundUserTurn(
        userInput: String,
        healthResourceContext: String?,
        buildResult: RuntimeMessagesBuildResult
    ) -> [AIRuntimeMessage] {
        let question = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = healthResourceContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 本轮既无问题也无健康上下文，直接沿用历史 runtime 消息
        guard question.isEmpty == false || prefix.isEmpty == false else { return buildResult.messages }

        var messages = buildResult.messages

        // 历史中尚无 user，或索引越界：追加一条合并后的 user
        guard let turn = buildResult.lastUserTurn, messages.indices.contains(turn.index) else {
            let content = mergeOutboundContent(prefix: prefix, base: question)
            guard content.isEmpty == false else { return messages }
            messages.append(AIRuntimeMessage(role: .user, content: content))
            return messages
        }

        let lastIndex = turn.index
        // 最后一条不是 user（异常兜底）：同样追加，不覆盖非 user 消息
        guard messages[lastIndex].role == .user else {
            let content = mergeOutboundContent(prefix: prefix, base: question)
            guard content.isEmpty == false else { return messages }
            messages.append(AIRuntimeMessage(role: .user, content: content))
            return messages
        }

        // 多模态：只更新 text part，不替换整条 message（避免丢掉 inline 图片）
        if turn.source == .directMultimodal {
            if prefix.isEmpty {
                return applyCurrentUserInput(question, to: messages)
            }
            messages.insert(AIRuntimeMessage(role: .user, content: prefix), at: lastIndex)
            if question.isEmpty == false {
                return applyCurrentUserInput(question, to: messages)
            }
            return messages
        }

        let existing = messages[lastIndex].content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let base: String
        switch turn.source {
        case .plainText:
            base = question.isEmpty ? existing : question
        case .localOCRAttachmentEnhanced,
             .healthResourceEnhanced,
             .unknownEnhanced:
            base = existing.isEmpty ? question : existing
        case .directMultimodal:
            return messages
        }

        let merged = mergeOutboundContent(prefix: prefix, base: base)
        guard merged.isEmpty == false else { return messages }
        messages[lastIndex] = AIRuntimeMessage(role: .user, content: merged)
        return messages
    }

    /// 合并出站前缀与正文，避免健康上下文重复拼接。
    private static func mergeOutboundContent(prefix: String, base: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrefix.isEmpty { return trimmedBase }
        if trimmedBase.isEmpty { return trimmedPrefix }
        // 正文已含相同前缀时不再重复
        if trimmedBase.hasPrefix(trimmedPrefix) { return trimmedBase }
        return "\(trimmedPrefix)\n\n\(trimmedBase)"
    }

    /// 记录本轮 user 组包摘要（不打印完整 OCR，避免敏感信息进日志）。
    private func logOutboundUserTurnMerge(
        buildResult: RuntimeMessagesBuildResult,
        loopMessages: [AIRuntimeMessage],
        healthResourceContext: String?
    ) {
        let turn = buildResult.lastUserTurn
        let lastContent: String = {
            guard let turn, loopMessages.indices.contains(turn.index) else { return "" }
            return loopMessages[turn.index].content ?? ""
        }()
        let appliedHealthContext = healthResourceContext?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let preservedEnhanced = turn?.preservedEnhancedContentAfterMerge ?? false
        logger.debug(
            """
            AI组包 user turn merge: lastUserSource=\(turn.map { String(describing: $0.source) } ?? "-"), \
            hasLocalOCR=\(turn?.hasLocalOCRContext ?? false), hasAttachment=\(turn?.hasAttachmentContext ?? false), \
            alreadyContainsCurrentUserInput=\(turn?.alreadyContainsCurrentUserInput ?? false), \
            appliedHealthContext=\(appliedHealthContext), preservedEnhancedContent=\(preservedEnhanced), \
            finalUserLength=\(lastContent.count)
            """,
            module: .aiConfig
        )
    }

    private static func applyCurrentUserInput(
        _ userInput: String,
        to messages: [AIRuntimeMessage]
    ) -> [AIRuntimeMessage] {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return messages }
        guard messages.isEmpty == false else {
            return [AIRuntimeMessage(role: .user, content: trimmed)]
        }
        var next = messages
        guard let lastIndex = next.indices.last, next[lastIndex].role == .user else {
            next.append(AIRuntimeMessage(role: .user, content: trimmed))
            return next
        }
        let last = next[lastIndex]
        if last.contentParts?.isEmpty == false {
            var parts = last.contentParts ?? []
            if let textIndex = parts.firstIndex(where: { $0.type == "text" }) {
                parts[textIndex] = .textPart(trimmed)
            } else {
                parts.insert(.textPart(trimmed), at: 0)
            }
            next[lastIndex] = AIRuntimeMessage(role: .user, content: nil, contentParts: parts)
        } else {
            next[lastIndex] = AIRuntimeMessage(role: .user, content: trimmed)
        }
        return next
    }

    private func makeRuntimeMessages(
        from history: [ChatMessage],
        systemPrompt: String?,
        memberContextSummary: String,
        reasoning: AIRuntimeReasoningOptions,
        deliverMultimodalImages: Bool,
        sendsOriginalImagesToAI: Bool,
        maxMessages: Int?
    ) async -> RuntimeMessagesBuildResult {
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

        var lastUserTurn: LastUserTurnComposition?

        for chatMessage in effectiveHistory where chatMessage.role != .system {
            let build = await buildRuntimeMessage(
                from: chatMessage,
                deliverMultimodalImages: deliverMultimodalImages,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI
            )
            runtimeMessages.append(build.message)
            if let flags = build.userTurnFlags {
                lastUserTurn = LastUserTurnComposition(
                    index: runtimeMessages.count - 1,
                    source: flags.source,
                    alreadyContainsCurrentUserInput: flags.alreadyContainsCurrentUserInput,
                    hasAttachmentContext: flags.hasAttachmentContext,
                    hasLocalOCRContext: flags.hasLocalOCRContext
                )
            }
        }
        return RuntimeMessagesBuildResult(messages: runtimeMessages, lastUserTurn: lastUserTurn)
    }

    private struct RuntimeMessageBuild: Sendable {
        let message: AIRuntimeMessage
        let userTurnFlags: LastUserTurnFlags?
    }

    private struct LastUserTurnFlags: Sendable {
        let source: LastUserTurnSource
        let alreadyContainsCurrentUserInput: Bool
        let hasAttachmentContext: Bool
        let hasLocalOCRContext: Bool
    }

    private func buildRuntimeMessage(
        from message: ChatMessage,
        deliverMultimodalImages: Bool,
        sendsOriginalImagesToAI: Bool
    ) async -> RuntimeMessageBuild {
        let messageText = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let messageAttachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
        let hasAttachmentContext = messageAttachments.isEmpty == false
        let hasHealthResourceBlocks = message.blocks.contains { $0.kind == .healthResourceReference }

        // 多模态模式：从本地缓存读取 JPEG 字节并内联 base64（不向模型发送远端 URL）
        if deliverMultimodalImages, message.role == .user {
            if let parts = await buildMultimodalParts(
                from: message,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI
            ) {
                return RuntimeMessageBuild(
                    message: AIRuntimeMessage(role: .user, content: nil, contentParts: parts),
                    userTurnFlags: LastUserTurnFlags(
                        source: .directMultimodal,
                        alreadyContainsCurrentUserInput: messageText.isEmpty == false,
                        hasAttachmentContext: true,
                        hasLocalOCRContext: false
                    )
                )
            }
        }

        // LocalOCR 模式：非多模态但有图片附件时，从附件中提取 OCR 文本拼接
        if message.role == .user, hasAttachmentContext {
            let ocrBuild = buildLocalOCRContent(from: message)
            if ocrBuild.content != messageText {
                return RuntimeMessageBuild(
                    message: AIRuntimeMessage(role: .user, content: ocrBuild.content),
                    userTurnFlags: LastUserTurnFlags(
                        source: .localOCRAttachmentEnhanced,
                        alreadyContainsCurrentUserInput: ocrBuild.includesUserInput,
                        hasAttachmentContext: true,
                        hasLocalOCRContext: ocrBuild.ocrTextCount > 0
                    )
                )
            }
            return RuntimeMessageBuild(
                message: AIRuntimeMessage(role: .user, content: messageText),
                userTurnFlags: LastUserTurnFlags(
                    source: .unknownEnhanced,
                    alreadyContainsCurrentUserInput: messageText.isEmpty == false,
                    hasAttachmentContext: true,
                    hasLocalOCRContext: false
                )
            )
        }

        let runtime = AIRuntimeMessage(role: message.role.runtimeRole, content: messageText)
        if message.role == .user {
            let source: LastUserTurnSource = hasHealthResourceBlocks ? .healthResourceEnhanced : .plainText
            return RuntimeMessageBuild(
                message: runtime,
                userTurnFlags: LastUserTurnFlags(
                    source: source,
                    alreadyContainsCurrentUserInput: messageText.isEmpty == false,
                    hasAttachmentContext: false,
                    hasLocalOCRContext: false
                )
            )
        }
        return RuntimeMessageBuild(message: runtime, userTurnFlags: nil)
    }

    private func buildMultimodalParts(
        from message: ChatMessage,
        sendsOriginalImagesToAI: Bool
    ) async -> [AIRuntimeContentPart]? {
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
            let originalImageData: Data?
            if let parsed = att.sparkClientOSSFileUUIDAndFileName(),
               let localURL = await fileCacheManager.cachedFileURL(fileUUID: parsed.fileUUID, fileName: parsed.fileName),
               let data = try? Data(contentsOf: localURL) {
                originalImageData = data
            } else if let url = att.url,
                      let data = try? await URLSession.shared.data(from: url).0 {
                originalImageData = data
            } else {
                originalImageData = nil
            }
            guard let originalImageData else {
                logger.debug("多模态：无法取得图片字节（缓存或 URL），跳过", module: .aiConfig)
                return nil
            }

            let jpegData: Data?
            if sendsOriginalImagesToAI {
                jpegData = UIImage(data: originalImageData)?.jpegData(compressionQuality: 0.9)
                logger.debug("多模态：AI 使用原图 JPEG，bytes=\(jpegData?.count ?? 0)", module: .aiConfig)
            } else {
                let compressed = await Task.detached(priority: .utility) {
                    ChatAIImageCompressor.compressForAI(imageData: originalImageData)
                }.value
                jpegData = compressed ?? UIImage(data: originalImageData)?.jpegData(compressionQuality: 0.45)
                logger.debug(
                    "多模态：AI 使用压缩图，originalBytes=\(originalImageData.count), aiBytes=\(jpegData?.count ?? 0), targetBytes=\(ChatAIImageCompressor.defaultTargetByteCount)",
                    module: .aiConfig
                )
            }
            guard let jpegData else {
                logger.debug("多模态：无法生成 AI 图片 JPEG，跳过", module: .aiConfig)
                return nil
            }
            parts.append(.imageInlineJPEGBase64(jpegData.base64EncodedString()))
        }
        return parts.count > 1 ? parts : nil
    }

    /// LocalOCR 模式：从附件元数据中提取 OCR 文本，构造增强后的用户内容（结构化结果供组包元数据使用）。
    private func buildLocalOCRContent(from message: ChatMessage) -> LocalOCRContentBuildResult {
        let userText = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
            .filter { $0.isUserFileForLocalOCR }
        guard attachments.isEmpty == false else {
            return LocalOCRContentBuildResult(
                content: userText,
                includesUserInput: userText.isEmpty == false,
                attachmentCount: 0,
                ocrTextCount: 0
            )
        }

        var blocks: [String] = []
        var ocrTextCount = 0
        for attachment in attachments {
            let ocr = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if ocr.isEmpty == false { ocrTextCount += 1 }
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
        
        let includesUserInput = userText.isEmpty == false
        if includesUserInput {
            blocks.append("【用户输入】\n\(userText)")
        }

        let content = blocks.isEmpty ? userText : blocks.joined(separator: "\n\n")
        return LocalOCRContentBuildResult(
            content: content,
            includesUserInput: includesUserInput,
            attachmentCount: attachments.count,
            ocrTextCount: ocrTextCount
        )
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
                            toolArguments: nil,
                            toolInvocationArguments: nil,
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
                            toolArguments: nil,
                            toolInvocationArguments: nil,
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
                    toolArguments: trimmedToolCallArguments(call.arguments),
                    toolInvocationArguments: {
                        let parsed = toolHub.parseArguments(call.arguments)
                        return parsed.isEmpty ? nil : parsed
                    }(),
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
        toolArguments: String?,
        toolInvocationArguments: [String: String]? = nil,
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
                toolArguments: toolArguments,
                toolInvocationArguments: toolInvocationArguments,
                toolCallID: toolCallID
            )
        )
    }

    private func resolvedToolInvocationArguments(
        toolResult: ToolExecutionResult,
        callArguments: String
    ) -> [String: String]? {
        if let arguments = toolResult.arguments, arguments.isEmpty == false {
            return arguments
        }
        let parsed = toolHub.parseArguments(callArguments)
        return parsed.isEmpty ? nil : parsed
    }

    private func buildOutputBlocks(
        text: String,
        reasoning: String?,
        toolName: String?,
        toolContent: String?,
        executedTools: [ToolExecutionResult]
    ) -> [ChatMessageBlock] {
        var blocks: [ChatMessageBlock] = []

        for result in executedTools {
            let output = result.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard output.isEmpty == false else { continue }
            blocks.append(
                ChatMessageBlock(
                    kind: .tool,
                    text: output,
                    toolName: result.toolName,
                    toolInvocationArguments: result.arguments,
                    toolCallID: result.toolCallID
                )
            )
        }

        if executedTools.isEmpty,
           let toolContent = toolContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           toolContent.isEmpty == false {
            blocks.append(
                ChatMessageBlock(
                    kind: .tool,
                    text: toolContent,
                    toolName: toolName
                )
            )
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty == false {
            blocks.append(ChatMessageBlock(kind: .text, text: trimmedText))
        }
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

    /// 工具开始执行时展示的参数字段（与 `AIRuntimeToolCall.arguments` 一致，多为 JSON 字符串）。
    private func trimmedToolCallArguments(_ arguments: String) -> String? {
        arguments.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// 工具详情 / 气泡正文：同时包含调用参数与执行输出。
    private func toolCallDetail(arguments: String, output: String) -> String {
        let args = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let argsTitle = L10n.text("chat.bubble.tool.arguments", fallback: "参数")
        let outputTitle = L10n.text("chat.bubble.tool.output", fallback: "输出")
        if args.isEmpty { return out }
        if out.isEmpty { return "\(argsTitle)\n\(args)" }
        return "\(argsTitle)\n\(args)\n\n\(outputTitle)\n\(out)"
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

// MARK: - Runtime message composition (LocalOCR / outbound merge)

private struct RuntimeMessagesBuildResult: Sendable {
    var messages: [AIRuntimeMessage]
    var lastUserTurn: LastUserTurnComposition?
}

private struct LocalOCRContentBuildResult: Sendable {
    let content: String
    let includesUserInput: Bool
    let attachmentCount: Int
    let ocrTextCount: Int
}

private struct LastUserTurnComposition: Sendable {
    let index: Int
    let source: LastUserTurnSource
    let alreadyContainsCurrentUserInput: Bool
    let hasAttachmentContext: Bool
    let hasLocalOCRContext: Bool

    /// 合并后是否保留了构造阶段的增强正文（不依赖 `【图片识别】` 等字符串 marker）。
    var preservedEnhancedContentAfterMerge: Bool {
        switch source {
        case .plainText:
            return false
        case .localOCRAttachmentEnhanced:
            return hasLocalOCRContext || hasAttachmentContext
        case .directMultimodal:
            return hasAttachmentContext
        case .healthResourceEnhanced, .unknownEnhanced:
            return hasAttachmentContext || hasLocalOCRContext || alreadyContainsCurrentUserInput
        }
    }
}

private enum LastUserTurnSource: Sendable {
    case plainText
    case localOCRAttachmentEnhanced
    case directMultimodal
    case healthResourceEnhanced
    case unknownEnhanced
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
