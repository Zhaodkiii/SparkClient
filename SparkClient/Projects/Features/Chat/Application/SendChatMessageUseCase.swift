import Foundation

struct SendChatMessageUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let chatSyncSupervisor: ChatSyncSupervisor
    let buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase
    let toolEventInterpreter: ChatToolEventInterpreter
    let fileTransferService: FileTransferService
    let ocrOrchestrator: OCROrchestrator
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    init(
        repository: any ChatRepository,
        orchestrator: ChatOrchestrator,
        chatSyncSupervisor: ChatSyncSupervisor,
        buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase,
        toolEventInterpreter: ChatToolEventInterpreter? = nil,
        fileTransferService: FileTransferService,
        ocrOrchestrator: OCROrchestrator,
        aiConfigCenter: AIConfigCenter,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.orchestrator = orchestrator
        self.chatSyncSupervisor = chatSyncSupervisor
        self.buildMemberContextSummaryUseCase = buildMemberContextSummaryUseCase
        self.logger = logger
        self.toolEventInterpreter = toolEventInterpreter ?? ChatToolEventInterpreter(logger: logger)
        self.fileTransferService = fileTransferService
        self.ocrOrchestrator = ocrOrchestrator
        self.aiConfigCenter = aiConfigCenter
    }

    func execute(
        threadID: UUID?,
        memberID: Int? = nil,
        userInput: String,
        composerAttachments: [ChatComposerAttachmentPreview] = [],
        preparedAttachments: [ChatPreparedAttachment] = [],
        selectedChatModelName: String? = nil,
        assistantClientMessageID: UUID,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        cancellationToken: AIRuntimeCancellationToken? = nil,
        onImageUploadProgress: (@Sendable (UUID, Double) -> Void)? = nil,
        onUserMessagePersisted: (@Sendable (_ snapshot: ChatThreadSnapshot) async -> Void)? = nil,
        onAssistantPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil
    ) async throws -> ChatThreadSnapshot {
        let sanitizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedInput.isEmpty == false || composerAttachments.isEmpty == false else {
            throw ChatFeatureError.emptyInput
        }

        let catalogSnapshot = await aiConfigCenter.currentSnapshot()
        let bundles = try await aiConfigCenter.effectiveScenarioBundles()
        let start = Date()
        logger.info(
            "sendMessage 开始，thread=\(shortID(threadID)), member=\(shortID(memberID)), inputLength=\(sanitizedInput.count), attachments=\(composerAttachments.count)",
            module: .general
        )

        do {
            try cancellationToken?.checkCancellation()
            let thread = try await resolveThread(
                existingThreadID: threadID,
                memberID: memberID,
                firstUserInput: sanitizedInput,
                defaultImageDeliveryRaw: catalogSnapshot.defaultThreadImageDeliveryModeRaw
            )
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

            let (supportsMultimodal, providerCompany) = bundles.chatMultimodalCapabilities(selectedModelName: resolvedRow.name)
            let effectiveMode = effectiveChatImageDeliveryMode(
                threadMode: thread.imageDeliveryMode,
                supportsMultimodal: supportsMultimodal
            )
            let deliverMultimodal = effectiveMode == .directMultimodal
                && supportsMultimodal
                && composerAttachments.isEmpty == false

            let preparedByID = Dictionary(uniqueKeysWithValues: preparedAttachments.map { ($0.previewID, $0) })
            var chatAttachments: [ChatAttachment] = []

            for preview in composerAttachments {
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

                let record = try await fileTransferService.upload(
                    ManagedFileUploadPayload(
                        data: preview.data,
                        fileName: preview.displayName,
                        businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
                        businessID: preview.id.uuidString,
                        isPublic: false,
                        onUploadProgress: { progress in
                            onImageUploadProgress?(preview.id, progress)
                        }
                    )
                )
                let ocrResult: OCRRecognition
                if preview.kind == .image {
                    ocrResult = try await ocrOrchestrator.recognize(
                        imageData: preview.data,
                        options: .fastPreview
                    )
                } else {
                    ocrResult = OCRRecognition(text: "", selectedEngine: "none", outputs: [])
                }
                let publicURL = await fileTransferService.publicHTTPSURLForObjectKey(record.objectKey)
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

            // 落库的 content 始终只保存用户原始输入（不包含 OCR 拼接文本）
            let persistedContent = sanitizedInput

            let clientMessageID = UUID()
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .user,
                kind: .text,
                content: persistedContent,
                attachments: chatAttachments,
                reasoningContent: nil,
                reasoningDurationMs: nil,
                reasoningExpanded: false,
                reasoningVisibility: .full,
                clientMessageID: clientMessageID,
                serverMessageID: nil,
                deliveryState: .pending
            )
            logger.debug(
                "用户消息已入库，thread=\(shortID(thread.id)), clientMessageID=\(shortID(clientMessageID))",
                module: .general
            )

            Task {
                await OutboxCoordinator.pushPendingMessages(
                    chatSyncSupervisor: chatSyncSupervisor,
                    logger: logger
                )
            }

            let history = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            if let onUserMessagePersisted {
                await onUserMessagePersisted(
                    ChatThreadSnapshot(thread: thread, messages: history)
                )
            }
            let contextMemberID = thread.memberID ?? memberID
            let memberContextSummary: String
            if let contextMemberID {
                memberContextSummary = await buildMemberContextSummaryUseCase.execute(memberID: contextMemberID, limit: 6)
            } else {
                memberContextSummary = ""
            }
            logger.debug(
                "准备 AI 编排，thread=\(shortID(thread.id)), history=\(history.count), memberContextLength=\(memberContextSummary.count), multimodal=\(deliverMultimodal)",
                module: .general
            )

            let textForTools = sanitizedInput

            let output = try await orchestrator.generateReply(
                userInput: textForTools,
                history: history,
                memberContextSummary: memberContextSummary,
                memberID: contextMemberID,
                threadID: thread.id,
                assistantMessageClientID: assistantClientMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                preferredModelName: resolvedRow.name,
                temperature: thread.temperature,
                topP: thread.topP,
                maxTokens: thread.maxTokens,
                maxMessages: thread.maxMessages,
                cancellationToken: cancellationToken,
                deliverMultimodalImages: deliverMultimodal,
                providerCompanyUppercased: providerCompany,
                onPartial: onAssistantPartial
            )
            logger.info(
                "AI 编排完成，thread=\(shortID(thread.id)), kind=\(output.kind.rawValue), outputLength=\(output.text.count)",
                module: .general
            )

            let reasoningTrimmed = output.reasoningText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let interpreted = toolEventInterpreter.interpret(
                kind: output.kind,
                text: output.text,
                toolName: output.toolName,
                toolContent: output.toolContent
            )
            if interpreted.knowledgeCardAttachmentCount > 0 {
                logger.debug(
                    "已生成知识卡预览附件，thread=\(shortID(thread.id)), count=\(interpreted.knowledgeCardAttachmentCount)",
                    module: .general
                )
            }
            if interpreted.richAttachmentCount > 0 {
                logger.debug(
                    "已生成富卡片附件，thread=\(shortID(thread.id)), count=\(interpreted.richAttachmentCount)",
                    module: .general
                )
            }
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .assistant,
                kind: output.kind,
                content: output.text,
                attachments: interpreted.attachments,
                reasoningContent: reasoningTrimmed.flatMap { $0.isEmpty ? nil : $0 },
                reasoningDurationMs: output.reasoningDurationMs,
                reasoningExpanded: false,
                reasoningVisibility: .full,
                clientMessageID: assistantClientMessageID,
                serverMessageID: nil,
                deliveryState: .pending
            )

            if let notice = finishReasonNoticeText(output.finishReason) {
                _ = try await repository.appendMessage(
                    threadID: thread.id,
                    role: .system,
                    kind: .system,
                    content: notice,
                    attachments: [],
                    reasoningContent: nil,
                    reasoningDurationMs: nil,
                    reasoningExpanded: false,
                    reasoningVisibility: .full,
                    clientMessageID: UUID(),
                    serverMessageID: nil,
                    deliveryState: .pending
                )
                logger.warning("AI 完成原因需要提示，thread=\(shortID(thread.id)), finishReason=\(output.finishReason ?? "-")", module: .general)
            }

            await OutboxCoordinator.pushPendingMessages(
                chatSyncSupervisor: chatSyncSupervisor,
                logger: logger
            )

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
            let cost = Date().timeIntervalSince(start)
            logger.error("sendMessage 失败，cost=\(format(cost))s error=\(error.localizedDescription)", module: .general)
            throw error
        }
    }

    func pushPendingMessages(source: String) async {
        logger.debug("触发对话待推送消息同步，source=\(source)", module: .general)
        await OutboxCoordinator.pushPendingMessages(
            chatSyncSupervisor: chatSyncSupervisor,
            logger: logger
        )
    }

    func executeRegenerateReply(
        threadID: UUID,
        memberID: Int? = nil,
        selectedChatModelName: String? = nil,
        assistantClientMessageID: UUID,
        inference: ChatOrchestratorInferenceOptions = .default,
        modelReasoning: ChatModelReasoningContext = .unknown,
        cancellationToken: AIRuntimeCancellationToken? = nil,
        onAssistantPartial: (@Sendable (ChatAssistantPartialDelta) async -> Void)? = nil
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

            let (supportsMultimodal, providerCompany) = bundles.chatMultimodalCapabilities(selectedModelName: resolvedRow.name)
            let effectiveMode = effectiveChatImageDeliveryMode(
                threadMode: thread.imageDeliveryMode,
                supportsMultimodal: supportsMultimodal
            )
            let deliverMultimodal = effectiveMode == .directMultimodal
                && supportsMultimodal
                && latestUserMessage.attachments.contains(where: \.isUserImageForMultimodal)

            let contextMemberID = thread.memberID ?? memberID
            let memberContextSummary: String
            if let contextMemberID {
                memberContextSummary = await buildMemberContextSummaryUseCase.execute(memberID: contextMemberID, limit: 6)
            } else {
                memberContextSummary = ""
            }

            let output = try await orchestrator.generateReply(
                userInput: latestUserMessage.content,
                history: replayHistory,
                memberContextSummary: memberContextSummary,
                memberID: contextMemberID,
                threadID: thread.id,
                assistantMessageClientID: assistantClientMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                preferredModelName: resolvedRow.name,
                temperature: thread.temperature,
                topP: thread.topP,
                maxTokens: thread.maxTokens,
                maxMessages: thread.maxMessages,
                cancellationToken: cancellationToken,
                deliverMultimodalImages: deliverMultimodal,
                providerCompanyUppercased: providerCompany,
                onPartial: onAssistantPartial
            )

            let reasoningTrimmed = output.reasoningText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let interpreted = toolEventInterpreter.interpret(
                kind: output.kind,
                text: output.text,
                toolName: output.toolName,
                toolContent: output.toolContent
            )
            _ = try await repository.appendMessage(
                threadID: thread.id,
                role: .assistant,
                kind: output.kind,
                content: output.text,
                attachments: interpreted.attachments,
                reasoningContent: reasoningTrimmed.flatMap { $0.isEmpty ? nil : $0 },
                reasoningDurationMs: output.reasoningDurationMs,
                reasoningExpanded: false,
                reasoningVisibility: .full,
                clientMessageID: assistantClientMessageID,
                serverMessageID: nil,
                deliveryState: .pending
            )

            if let notice = finishReasonNoticeText(output.finishReason) {
                _ = try await repository.appendMessage(
                    threadID: thread.id,
                    role: .system,
                    kind: .system,
                    content: notice,
                    attachments: [],
                    reasoningContent: nil,
                    reasoningDurationMs: nil,
                    reasoningExpanded: false,
                    reasoningVisibility: .full,
                    clientMessageID: UUID(),
                    serverMessageID: nil,
                    deliveryState: .pending
                )
                logger.warning("重新生成完成原因需要提示，thread=\(shortID(thread.id)), finishReason=\(output.finishReason ?? "-")", module: .general)
            }

            await OutboxCoordinator.pushPendingMessages(
                chatSyncSupervisor: chatSyncSupervisor,
                logger: logger
            )

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
            if let memberID, active.memberID != memberID {
                let title = String(firstUserInput.prefix(18))
                let created = await repository.createThread(
                    memberID: memberID,
                    title: title.isEmpty ? promptLocalizer.newThreadTitle() : title,
                    imageDeliveryModeRaw: defaultImageDeliveryRaw
                )
                await repository.setActiveThread(id: created.id)
                return created
            }
            return active
        }

        let title = String(firstUserInput.prefix(18))
        let created = await repository.createThread(
            memberID: memberID,
            title: title.isEmpty ? promptLocalizer.newThreadTitle() : title,
            imageDeliveryModeRaw: defaultImageDeliveryRaw
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
