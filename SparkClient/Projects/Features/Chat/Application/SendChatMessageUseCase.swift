import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase
    let toolEventInterpreter: ChatToolEventInterpreter
    let fileTransferService: FileTransferService
    let ocrOrchestrator: OCROrchestrator
    let aiConfigCenter: AIConfigCenter
    let retrieveMemoryUseCase: RetrieveMemoryUseCase
    let messageRunActor: MessageRunActor
    let medicalQueryAPI: SparkMedicalQueryAPI
    let logger: Logger

    init(
        repository: any ChatRepository,
        orchestrator: ChatOrchestrator,
        buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase,
        toolEventInterpreter: ChatToolEventInterpreter? = nil,
        fileTransferService: FileTransferService,
        ocrOrchestrator: OCROrchestrator,
        aiConfigCenter: AIConfigCenter,
        retrieveMemoryUseCase: RetrieveMemoryUseCase,
        messageRunActor: MessageRunActor,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.orchestrator = orchestrator
        self.buildMemberContextSummaryUseCase = buildMemberContextSummaryUseCase
        self.logger = logger
        self.toolEventInterpreter = toolEventInterpreter ?? ChatToolEventInterpreter(logger: logger)
        self.fileTransferService = fileTransferService
        self.ocrOrchestrator = ocrOrchestrator
        self.aiConfigCenter = aiConfigCenter
        self.retrieveMemoryUseCase = retrieveMemoryUseCase
        self.messageRunActor = messageRunActor
        self.medicalQueryAPI = medicalQueryAPI
    }

    /// 发送消息核心业务方法：处理输入、上传附件、保存消息、调用AI生成、返回对话快照
    func execute(
        threadID: UUID?,                     // 对话线程ID
        memberID: Int? = nil,                // 成员ID
        userInput: String,                   // 用户输入文本
        composerAttachments: [ChatComposerAttachmentPreview] = [],  // 编辑区附件
        preparedAttachments: [ChatPreparedAttachment] = [],        // 已预处理的附件
        healthResourceRefs: [HealthResourceRef] = [],
        selectedChatModelName: String? = nil, // 用户选择的模型名称
        assistantClientMessageID: UUID,      // 助手消息客户端ID
        inference: ChatOrchestratorInferenceOptions = .default,    // 推理选项
        modelReasoning: ChatModelReasoningContext = .unknown,      // 模型推理上下文
        smallTask: SmallTask? = nil,          // 小任务（可选）
        sendsOriginalImagesToAI: Bool = false, // 本次多模态发送是否使用原图
        cancellationToken: AIRuntimeCancellationToken? = nil,      // 取消令牌
        onImageUploadProgress: (@Sendable (UUID, Double) -> Void)? = nil,           // 图片上传进度
        onUserMessagePersisted: (@Sendable (_ snapshot: ChatThreadSnapshot) async -> Void)? = nil,  // 用户消息落库回调
        onAssistantPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil,         // AI流式返回回调
        cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async throws -> ChatThreadSnapshot {
        // 清理用户输入首尾空白
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // 校验：输入不能为空 + 无附件 + 无小任务，直接抛空输入错误
        guard sanitizedInput.isEmpty == false
            || composerAttachments.isEmpty == false
            || smallTask != nil
            || healthResourceRefs.isEmpty == false
        else {
            throw ChatFeatureError.emptyInput
        }

        // 获取AI配置快照
        let catalogSnapshot = await aiConfigCenter.currentSnapshot()
        // 获取生效的场景模型配置
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        let start = Date()
        // 日志：发送消息开始
        logger.info(
            "sendMessage 开始，thread=\(shortID(threadID)), member=\(shortID(memberID)), inputLength=\(sanitizedInput.count), attachments=\(composerAttachments.count), healthRefs=\(healthResourceRefs.count)",
            module: .general
        )

        do {
            // 检查是否被取消
            try cancellationToken?.checkCancellation()
            // 获取或创建对话线程
            let thread = try await resolveThread(
                existingThreadID: threadID,
                memberID: memberID,
                firstUserInput: smallTask?.name ?? sanitizedInput,
                defaultImageDeliveryRaw: catalogSnapshot.defaultThreadImageDeliveryModeRaw
            )
            
            // 模型名称清洗处理
            let trimmedSelected = selectedChatModelName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let trimmedThreadModel = thread.currentModelName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // 确定优先使用的模型：用户选择 > 线程已有 > 默认
            let preferredName = (trimmedSelected?.isEmpty == false)
                ? trimmedSelected
                : ((trimmedThreadModel?.isEmpty == false) ? trimmedThreadModel : nil)
            // 获取匹配的模型配置，找不到则抛错
            guard let resolvedRow = bundles.resolveRow(for: .chat, preferredModelName: preferredName) else {
                throw AIConfigError.missingModelForScenario(.chat)
            }
            // 最终要持久化的模型名称
            let persistedModelName = trimmedSelected?.isEmpty == false
                ? trimmedSelected
                : (trimmedThreadModel?.isEmpty == false ? trimmedThreadModel : resolvedRow.name)
            let generationParameters = Self.resolveGenerationParameters(
                thread: thread,
                modelRow: resolvedRow
            )
            
            // 构建系统提示词
            let systemPrompt = await systemPromptWithRelevantMemory(
                base: ChatSystemPromptResolver().resolve(
                    sessionPrompt: thread.rolePrompt,
                    agentPrompt: resolvedRow.systemPrompt,
                    smallTask: smallTask
                ),
                query: sanitizedInput
            )

            // 如果线程模型和当前选择不一致，更新线程的模型配置
            if thread.currentModelName != persistedModelName {
                await repository.updateThreadGenerationConfig(
                    threadID: thread.id,
                    currentModelName: persistedModelName,
                    temperature: thread.temperature,
                    topP: thread.topP,
                    maxTokens: thread.maxTokens,
                    maxMessages: thread.maxMessages,
                    rolePrompt: thread.rolePrompt
                )
            }

            // 获取模型是否支持多模态、厂商信息
            let (supportsMultimodal, providerCompany) = bundles.chatMultimodalCapabilities(selectedModelName: resolvedRow.name)
            // 确定图片传递模式
            let effectiveMode = effectiveChatImageDeliveryMode(
                threadMode: thread.imageDeliveryMode,
                supportsMultimodal: supportsMultimodal
            )
            // 是否直接以多模态方式发送图片给AI
            let deliverMultimodal = effectiveMode == .directMultimodal
                && supportsMultimodal
                && composerAttachments.isEmpty == false

            // 把预处理附件转成字典，方便按ID查找
            let preparedByID = Dictionary(uniqueKeysWithValues: preparedAttachments.map { ($0.previewID, $0) })
            var chatAttachments: [ChatAttachment] = []

            // 遍历所有编辑区附件，上传并组装成可发送的聊天附件
            for preview in composerAttachments {
                // 如果附件已经预处理完成，直接复用
                if let prepared = preparedByID[preview.id] {
                    let publicURL = await fileTransferService.publicHTTPSURLForObjectKey(prepared.record.objectKey)
                    chatAttachments.append(
                        ChatSendAttachmentAssembly.makeAttachment(
                            kind: prepared.kind,
                            previewID: preview.id,
                            record: prepared.record,
                            ocrText: prepared.ocrText,
                            publicFullURL: publicURL
                        )
                    )
                    continue
                }

                // 上传附件到文件服务
                let record = try await fileTransferService.upload(
                    ManagedFileUploadPayload(
                        data: preview.data,
                        fileName: preview.displayName,
                        businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
                        businessId: preview.id.uuidString,
                        isPublic: false,
                        onUploadProgress: { progress in
                            onImageUploadProgress?(preview.id, progress)
                        }
                    )
                )
                
                // 图片进行OCR识别
                let ocrResult: OCRRecognition
                if preview.kind == .image {
                    ocrResult = try await ocrOrchestrator.recognize(
                        imageData: preview.data,
                        options: .fastPreview
                    )
                } else {
                    ocrResult = OCRRecognition(text: "", selectedEngine: "none", outputs: [])
                }
                
                // 获取公开访问URL
                let publicURL = await fileTransferService.publicHTTPSURLForObjectKey(record.objectKey)
                // 组装附件模型
                chatAttachments.append(
                    ChatSendAttachmentAssembly.makeAttachment(
                        kind: preview.kind,
                        previewID: preview.id,
                        record: record,
                        ocrText: ocrResult.text,
                        publicFullURL: publicURL
                    )
                )
            }

            // 小任务：构建卡片附件
            let smallTaskCardPayload = smallTask.map(ChatSmallTaskMessageCardPayload.init(task:))
            let smallTaskCardAttachment = smallTaskCardPayload?.encodedString().map {
                ChatAttachment(type: .smallTaskCard, text: $0)
            }
            // 小任务展示内容
            let smallTaskDisplayContent = smallTask.map { task in
                let brief = task.brief.trimmingCharacters(in: .whitespacesAndNewlines)
                return brief.isEmpty ? "小任务：\(task.name)" : "小任务：\(task.name)\n\(brief)"
            }

            // 最终附件 = 普通附件 + 小任务卡片
            let persistedAttachments = smallTaskCardAttachment.map { chatAttachments + [$0] } ?? chatAttachments
            let persistedContent = smallTask == nil ? sanitizedInput : (smallTaskDisplayContent ?? "")
            let now = Date()
            var userBlocks: [ChatMessageBlock] = []
            let trimmedPersistedContent = persistedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPersistedContent.isEmpty == false {
                userBlocks.append(
                    ChatMessageBlock(
                        kind: .text,
                        text: persistedContent,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            let galleryAttachments = persistedAttachments.filter { $0.type == .image }
            let fileAttachments = persistedAttachments.filter { $0.type == .pdf || $0.type == .file }
            if galleryAttachments.isEmpty == false {
                userBlocks.append(
                    ChatMessageBlock(
                        kind: .imageGallery,
                        attachments: galleryAttachments,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            if fileAttachments.isEmpty == false {
                userBlocks.append(
                    ChatMessageBlock(
                        kind: .fileAttachments,
                        attachments: fileAttachments,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            if let smallTaskCardPayload {
                userBlocks.append(
                    ChatMessageBlock(
                        kind: .smallTaskCard,
                        smallTaskCard: smallTaskCardPayload,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }

            let clientMessageID = UUID()
            for (index, ref) in healthResourceRefs.enumerated() {
                let payload = ref.toMessagePayload(refIndex: index + 1)
                userBlocks.append(
                    ChatMessageBlock(
                        id: ChatStableBlockID.healthResource(
                            messageID: clientMessageID,
                            resourceType: payload.resourceType,
                            resourceID: payload.resourceId,
                            memberID: payload.memberId
                        ),
                        kind: .healthResourceReference,
                        healthResourceReference: payload,
                        orderKey: Double(1000 + index),
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }

            // 保存用户消息到本地数据库
            _ = try await repository.appendMessage(
                ChatMessage(
                    threadID: thread.id,
                    role: .user,
                    blocks: userBlocks,
                    clientMessageID: clientMessageID,
                    serverMessageID: nil,
                    deliveryState: .pending,
                    modelName: "user"
                )
            )
            let healthBlockCount = userBlocks.filter { $0.kind == .healthResourceReference }.count
            logger.debug(
                "用户消息已入库，thread=\(shortID(thread.id)), clientMessageID=\(shortID(clientMessageID)), blocks=\(userBlocks.count), healthBlocks=\(healthBlockCount)",
                module: .general
            )

            // 加载当前对话所有历史消息
            let history = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            try await messageRunActor.startAssistantMessage(
                threadID: thread.id,
                assistantClientMessageID: assistantClientMessageID,
                modelName: resolvedRow.name
            )
            let visibleHistory = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            // 回调：用户消息已落库
            if let onUserMessagePersisted {
                await onUserMessagePersisted(
                    ChatThreadSnapshot(thread: thread, messages: visibleHistory)
                )
            }
            
            // 构建成员上下文摘要（问报告时由 healthResourceContext 承担，跳过多 kind 列表拉取）
            let contextMemberID = smallTask == nil ? thread.memberID : nil
            let memberContextSummary: String
            if let contextMemberID {
                if healthResourceRefs.isEmpty {
                    memberContextSummary = await buildMemberContextSummaryUseCase.execute(memberID: contextMemberID, limit: 6)
                } else {
                    memberContextSummary = ""
                }
            } else {
                memberContextSummary = ""
            }
            logger.debug(
                "准备 AI 编排，thread=\(shortID(thread.id)), history=\(history.count), memberContextLength=\(memberContextSummary.count), multimodal=\(deliverMultimodal)",
                module: .general
            )

            let outboundAssembler = ChatOutboundContextAssembler(medicalQueryAPI: medicalQueryAPI)
            var userQuestionForAI = smallTask.map { makeSmallTaskUserInput(task: $0, userInput: sanitizedInput) }
                ?? outboundAssembler.defaultUserQuestionWhenEmpty(
                    userInput: sanitizedInput,
                    healthResourceRefs: healthResourceRefs
                )
            let healthContextForAI = await outboundAssembler.assembleHealthResourceContext(
                refs: healthResourceRefs,
                threadMemberID: thread.memberID,
                cachedMemberCompleteData: cachedMemberCompleteData
            )
            if healthResourceRefs.isEmpty == false {
                if healthContextForAI == nil {
                    logger.warning(
                        "健康资料上下文解析为空，refs=\(healthResourceRefs.count)",
                        module: .general
                    )
                }
                logger.debug(
                    "问报告 AI 输入已组装，healthRefs=\(healthResourceRefs.count), questionLen=\(userQuestionForAI.count), contextLen=\(healthContextForAI?.count ?? 0)",
                    module: .general
                )
            }
            let aiHistory: [ChatMessage]
            let effectiveInference: ChatOrchestratorInferenceOptions
            let modelAllowedToolNames = allowedToolNames(from: resolvedRow.aiToolScenarios)
            if let smallTask {
                aiHistory = [
                    ChatMessage(
                        threadID: thread.id,
                        role: .user,
                        blocks: [.init(kind: .text, text: userQuestionForAI)],
                        deliveryState: .pending,
                        modelName: "user"
                    )
                ]
                effectiveInference = ChatOrchestratorInferenceOptions(
                    useTools: smallTask.toolList.isEmpty == false,
                    useKnowledgeBag: inference.useKnowledgeBag,
                    useWebSearch: inference.useWebSearch,
                    reasoningEnabled: inference.reasoningEnabled,
                    reasoningEffortTier: inference.reasoningEffortTier,
                    allowedToolNames: Set(smallTask.toolList).intersection(modelAllowedToolNames ?? Set(smallTask.toolList))
                )
            } else {
                aiHistory = history
                effectiveInference = inference.withAllowedToolNames(modelAllowedToolNames)
            }
            if let allowed = effectiveInference.allowedToolNames {
                logger.debug(
                    "模型工具白名单生效，model=\(resolvedRow.name), allowedTools=\(allowed.sorted().joined(separator: ",")), count=\(allowed.count)",
                    module: .aiConfig
                )
            }

            // MARK: 核心：调用AI编排器生成回复（流式）
            let output = try await orchestrator.generateReply(
                userInput: userQuestionForAI,
                healthResourceContext: healthContextForAI,
                history: aiHistory,
                memberContextSummary: memberContextSummary,
                memberID: contextMemberID,
                threadID: thread.id,
                assistantMessageClientID: assistantClientMessageID,
                inference: effectiveInference,
                modelReasoning: modelReasoning,
                systemPrompt: systemPrompt,
                preferredModelName: resolvedRow.name,
                temperature: generationParameters.temperature,
                topP: thread.topP,
                maxTokens: generationParameters.maxTokens,
                maxMessages: thread.maxMessages,
                cancellationToken: cancellationToken,
                deliverMultimodalImages: smallTask == nil && deliverMultimodal,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI,
                providerCompanyUppercased: providerCompany,
                onPartial: { delta in
                    await messageRunActor.apply(
                        .assistantPartial(delta, assistantClientMessageID: assistantClientMessageID)
                    )
                    if let onAssistantPartial {
                        await onAssistantPartial(delta)
                    }
                },
                messageRunActor: messageRunActor
            )
            logger.info(
                "AI 编排完成，thread=\(shortID(thread.id)), kind=\(output.kind.rawValue), outputLength=\(output.text.count)",
                module: .general
            )

            // 解析工具事件
            _ = toolEventInterpreter.interpret(
                kind: output.kind,
                text: output.text,
                toolName: output.toolName,
                toolContent: output.toolContent
            )
            let assistantBlocks = buildAssistantBlocks(
                outputBlocks: output.blocks,
                reasoningText: output.reasoningText,
                reasoningDurationMs: output.reasoningDurationMs
            )
            await messageRunActor.apply(
                .finalizeAssistantBlocks(assistantBlocks, assistantClientMessageID: assistantClientMessageID)
            )

            // 如果 AI 结束原因需要提示，写入本轮助手消息，避免额外插入 system 消息。
            if let notice = finishReasonNoticeText(output.finishReason) {
                await messageRunActor.appendTimelineNotice(
                    notice,
                    assistantClientMessageID: assistantClientMessageID
                )
                logger.warning("AI 完成原因需要提示，thread=\(shortID(thread.id)), finishReason=\(output.finishReason ?? "-")", module: .general)
            }

            // 加载最新线程与消息，返回快照
            guard let latestThread = await repository.loadThread(id: thread.id) else {
                throw ChatFeatureError.threadNotFound
            }
            let latestHistory = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "sendMessage 完成，thread=\(shortID(thread.id)), messages=\(latestHistory.count), cost=\(format(cost))s",
                module: .general
            )
            return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
        } catch {
            // 异常日志
            let cost = Date().timeIntervalSince(start)
            logger.error("sendMessage 失败，cost=\(format(cost))s error=\(error.localizedDescription)", module: .general)
            throw error
        }
    }

    func executeRegenerateReply(
        threadID: UUID,
        memberID: Int? = nil,
        selectedChatModelName: String? = nil,
        assistantClientMessageID: UUID,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        sendsOriginalImagesToAI: Bool = false,
        cancellationToken: AIRuntimeCancellationToken? = nil,
        onAssistantPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil,
        cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async throws -> ChatThreadSnapshot {
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        let start = Date()
        logger.info(
            "regenerateReply 开始，thread=\(shortID(threadID)), member=\(shortID(memberID))",
            module: .general
        )

        do {
            try cancellationToken?.checkCancellation()
            guard let thread = await repository.loadThread(id: threadID) else {
                throw ChatFeatureError.threadNotFound
            }
            let trimmedSelected = selectedChatModelName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let trimmedThreadModel = thread.currentModelName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let preferredName = (trimmedSelected?.isEmpty == false)
                ? trimmedSelected
                : ((trimmedThreadModel?.isEmpty == false) ? trimmedThreadModel : nil)
            guard let resolvedRow = bundles.resolveRow(for: .chat, preferredModelName: preferredName) else {
                throw AIConfigError.missingModelForScenario(.chat)
            }
            let persistedModelName = trimmedSelected?.isEmpty == false
                ? trimmedSelected
                : (trimmedThreadModel?.isEmpty == false ? trimmedThreadModel : resolvedRow.name)
            let generationParameters = Self.resolveGenerationParameters(
                thread: thread,
                modelRow: resolvedRow
            )
            let baseSystemPrompt = ChatSystemPromptResolver().resolve(
                sessionPrompt: thread.rolePrompt,
                agentPrompt: resolvedRow.systemPrompt,
                smallTask: nil
            )

            if thread.currentModelName != persistedModelName {
                await repository.updateThreadGenerationConfig(
                    threadID: thread.id,
                    currentModelName: persistedModelName,
                    temperature: thread.temperature,
                    topP: thread.topP,
                    maxTokens: thread.maxTokens,
                    maxMessages: thread.maxMessages,
                    rolePrompt: thread.rolePrompt
                )
            }

            let history = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            let replayHistory = history.filter { $0.deliveryState != .failed }
            guard let latestUserMessage = replayHistory.last(where: { $0.role == .user && $0.isTombstone == false }) else {
                throw ChatFeatureError.emptyInput
            }
            let replayUserInput = latestUserMessage.blocks
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let systemPrompt = await systemPromptWithRelevantMemory(
                base: baseSystemPrompt,
                query: replayUserInput
            )

            let (supportsMultimodal, providerCompany) = bundles.chatMultimodalCapabilities(selectedModelName: resolvedRow.name)
            let effectiveMode = effectiveChatImageDeliveryMode(
                threadMode: thread.imageDeliveryMode,
                supportsMultimodal: supportsMultimodal
            )
            let deliverMultimodal = effectiveMode == .directMultimodal
                && supportsMultimodal
                && latestUserMessage.blocks
                    .flatMap(\.attachments)
                    .contains(where: \.isUserImageForMultimodal)

            let contextMemberID = thread.memberID
            let replayHealthRefs = Self.healthResourceRefs(from: latestUserMessage.blocks)
            let memberContextSummary: String
            if let contextMemberID {
                if replayHealthRefs.isEmpty {
                    memberContextSummary = await buildMemberContextSummaryUseCase.execute(memberID: contextMemberID, limit: 6)
                } else {
                    memberContextSummary = ""
                }
            } else {
                memberContextSummary = ""
            }

            let effectiveInference = inference.withAllowedToolNames(
                allowedToolNames(from: resolvedRow.aiToolScenarios)
            )
            if let allowed = effectiveInference.allowedToolNames {
                logger.debug(
                    "模型工具白名单生效，model=\(resolvedRow.name), allowedTools=\(allowed.sorted().joined(separator: ",")), count=\(allowed.count)",
                    module: .aiConfig
                )
            }
            try await messageRunActor.startAssistantMessage(
                threadID: thread.id,
                assistantClientMessageID: assistantClientMessageID,
                modelName: resolvedRow.name
            )

            var healthContextForAI: String?
            if replayHealthRefs.isEmpty == false, let resolveMemberID = contextMemberID ?? replayHealthRefs.first?.memberID,
               resolveMemberID > 0 {
                let localCache = cachedMemberCompleteData?.memberId == resolveMemberID
                    ? cachedMemberCompleteData
                    : nil
                let resolved = await HealthResourceContextResolver(medicalQueryAPI: medicalQueryAPI)
                    .resolveContextText(
                        refs: replayHealthRefs,
                        memberID: resolveMemberID,
                        cachedCompleteData: localCache
                    )
                if resolved.isEmpty == false {
                    healthContextForAI = resolved
                }
            }

            let output = try await orchestrator.generateReply(
                userInput: replayUserInput,
                healthResourceContext: healthContextForAI,
                history: replayHistory,
                memberContextSummary: memberContextSummary,
                memberID: contextMemberID,
                threadID: thread.id,
                assistantMessageClientID: assistantClientMessageID,
                inference: effectiveInference,
                modelReasoning: modelReasoning,
                systemPrompt: systemPrompt,
                preferredModelName: resolvedRow.name,
                temperature: generationParameters.temperature,
                topP: thread.topP,
                maxTokens: generationParameters.maxTokens,
                maxMessages: thread.maxMessages,
                cancellationToken: cancellationToken,
                deliverMultimodalImages: deliverMultimodal,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI,
                providerCompanyUppercased: providerCompany,
                onPartial: { delta in
                    await messageRunActor.apply(
                        .assistantPartial(delta, assistantClientMessageID: assistantClientMessageID)
                    )
                    if let onAssistantPartial {
                        await onAssistantPartial(delta)
                    }
                },
                messageRunActor: messageRunActor
            )

            _ = toolEventInterpreter.interpret(
                kind: output.kind,
                text: output.text,
                toolName: output.toolName,
                toolContent: output.toolContent
            )
            let assistantBlocks = buildAssistantBlocks(
                outputBlocks: output.blocks,
                reasoningText: output.reasoningText,
                reasoningDurationMs: output.reasoningDurationMs
            )
            await messageRunActor.apply(
                .finalizeAssistantBlocks(assistantBlocks, assistantClientMessageID: assistantClientMessageID)
            )

            if let notice = finishReasonNoticeText(output.finishReason) {
                await messageRunActor.appendTimelineNotice(
                    notice,
                    assistantClientMessageID: assistantClientMessageID
                )
                logger.warning("重新生成完成原因需要提示，thread=\(shortID(thread.id)), finishReason=\(output.finishReason ?? "-")", module: .general)
            }

            guard let latestThread = await repository.loadThread(id: thread.id) else {
                throw ChatFeatureError.threadNotFound
            }
            let latestHistory = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "regenerateReply 完成，thread=\(shortID(thread.id)), messages=\(latestHistory.count), cost=\(format(cost))s",
                module: .general
            )
            return ChatThreadSnapshot(thread: latestThread, messages: latestHistory)
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error("regenerateReply 失败，cost=\(format(cost))s error=\(error.localizedDescription)", module: .general)
            throw error
        }
    }

    private func buildAssistantBlocks(
        outputBlocks: [ChatMessageBlock],
        reasoningText: String?,
        reasoningDurationMs: Int64?
    ) -> [ChatMessageBlock] {
        let now = Date()
        var blocks = outputBlocks
        if blocks.isEmpty {
            blocks = []
        }
        let trimmed = reasoningText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return blocks }
        blocks.append(
            ChatMessageBlock(
                kind: .deepThought,
                deepThoughtCard: ChatDeepThoughtCardPayload(
                    reasoningContent: trimmed,
                    reasoningDurationMs: reasoningDurationMs,
                    reasoningExpanded: false,
                    reasoningVisibility: .full
                ),
                createdAt: now,
                updatedAt: now
            )
        )
        return blocks
    }

    private func resolveThread(
        existingThreadID: UUID?,
        memberID: Int?,
        firstUserInput: String,
        defaultImageDeliveryRaw: String
    ) async throws -> ChatThread {
        let promptLocalizer = PromptLocalizer()
        if let existingThreadID {
            if let thread = await repository.loadThread(id: existingThreadID) {
                await repository.setActiveThread(id: existingThreadID)
                return thread
            }
            throw ChatFeatureError.threadNotFound
        }

        if let active = await repository.loadActiveThread() {
            return active
        }

        let title = String(firstUserInput.prefix(18))
        let created = await repository.createThread(
            memberID: nil,
            title: title.isEmpty ? promptLocalizer.newThreadTitle() : title,
            imageDeliveryModeRaw: defaultImageDeliveryRaw,
            rolePrompt: ""
        )
        await repository.setActiveThread(id: created.id)
        return created
    }

    private func finishReasonNoticeText(_ rawReason: String?) -> String? {
        let reason = rawReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard reason.isEmpty == false else { return nil }

        if reason == "length" || reason.contains("max_token") {
            return L10n.text("chat.finish_reason.length")
        }
        if reason == "sensitive" || reason == "content_filter" || reason.contains("safety") {
            return L10n.text("chat.finish_reason.sensitive")
        }
        return nil
    }

    func finalizeInterruptedAssistantMessage(
        statusCard: ChatAssistantStatusCardPayload,
        assistantClientMessageID: UUID
    ) async -> Bool {
        await messageRunActor.finalizeInterruptedAssistantMessage(
            statusCard: statusCard,
            assistantClientMessageID: assistantClientMessageID
        )
    }

    private func makeSmallTaskUserInput(task: SmallTask, userInput: String) -> String {
        var blocks = ["请执行小任务：\(task.name)"]
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInput.isEmpty == false {
            blocks.append("【用户补充输入】\n\(trimmedInput)")
        }
        return blocks.joined(separator: "\n\n")
    }

    private func systemPromptWithRelevantMemory(base: String, query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return base }
        do {
            let results = try await retrieveMemoryUseCase.execute(keyword: trimmed)
            let memorySection = MemoryPromptBuilder().makePromptSection(results: results)
            guard memorySection.isEmpty == false else { return base }
            return [base, memorySection].joined(separator: "\n\n")
        } catch {
            logger.warning("记忆检索注入失败：\(error.localizedDescription)", module: .aiConfig)
            return base
        }
    }

    private func allowedToolNames(from storedToolNames: [String]) -> Set<String>? {
        if storedToolNames.isEmpty {
            return nil
        }
        if storedToolNames.contains(SparkToolName.noSelectionSentinel) {
            return []
        }
        let normalized = Set(storedToolNames).intersection(Set(SparkToolName.all))
        return normalized.isEmpty ? nil : normalized
    }

    private static func healthResourceRefs(from blocks: [ChatMessageBlock]) -> [HealthResourceRef] {
        blocks.compactMap { block -> (Int, HealthResourceRef)? in
            guard case .healthResourceReference(let payload) = block.payload,
                  let type = HealthResourceType(rawValue: payload.resourceType) else {
                return nil
            }
            let ref = HealthResourceRef(
                type: type,
                resourceID: payload.resourceId,
                memberID: payload.memberId,
                displayTitle: L10n.text(type.localizationKey),
                displaySubtitle: ""
            )
            return (payload.refIndex, ref)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    private static func resolveGenerationParameters(
        thread: ChatThread,
        modelRow: AIScenarioRemoteModelRow
    ) -> (temperature: Double, maxTokens: Int) {
        if modelRow.identity == AIModelIdentity.agent.rawValue {
            return (modelRow.temperature, modelRow.maxTokens)
        }
        return (
            thread.temperature ?? modelRow.temperature,
            thread.maxTokens ?? modelRow.maxTokens
        )
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}

private extension ChatOrchestratorInferenceOptions {
    func withAllowedToolNames(_ allowedToolNames: Set<String>?) -> Self {
        var copy = self
        copy.allowedToolNames = allowedToolNames
        return copy
    }
}
