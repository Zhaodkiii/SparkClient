import Combine
import Foundation

struct ChatComposerModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let modelName: String
    let title: String
    let iconSystemName: String

    init(modelName: String, title: String, iconSystemName: String = "cpu") {
        self.id = modelName
        self.modelName = modelName
        self.title = title
        self.iconSystemName = iconSystemName
    }
}

@MainActor
final class ChatDetailViewModel: ObservableObject {
    private enum MessagePagingConfig {
        static let initialLimit = 6
        static let loadMoreLimit = 10
    }

    private let stateStore: ChatStateStore
    private let memberContextStore: MemberContextStore
    private let chatRepository: any ChatRepository
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let fileTransferService: FileTransferService
    private let ocrOrchestrator: OCROrchestrator
    private let retryFailedMessageUseCase: RetryFailedMessageUseCase
    private let syncChatUseCase: SyncChatUseCase
    private let updateChatMessageAttachmentsUseCase: UpdateChatMessageAttachmentsUseCase
    private let notificationClient: any NotificationClient
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    private let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    private let logger: Logger
    private var isRealtimeActive = false
    private var composerAttachmentTasks: [UUID: Task<Void, Never>] = [:]

    /// 结构化医疗卡片保存中（用于按钮 Progress）。
    @Published private(set) var savingStructuredHealthCardIDs: Set<UUID> = []

    /// 对话场景可选模型行（远程场景 + 本地/智能体模型），供 Hanlin 输入栏展示。
    @Published private(set) var chatScenarioModels: [ChatComposerModelOption] = []
    /// 当前会话输入栏关联模型的推理能力（用于思考开关展示策略）。
    @Published private(set) var reasoningToolbarContext: ChatModelReasoningContext = .unknown
    /// 当前会话在列表中的图片送达方式（用于工具栏菜单展示）。
    @Published private(set) var threadImageDeliveryMode: ChatThreadImageDeliveryMode = .directMultimodal
    /// 当前所选对话模型是否支持多模态（用于置灰「直发」选项）。
    @Published private(set) var currentModelSupportsMultimodal: Bool = false

    init(
        stateStore: ChatStateStore,
        memberContextStore: MemberContextStore,
        chatRepository: any ChatRepository,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        fileTransferService: FileTransferService,
        ocrOrchestrator: OCROrchestrator,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        syncChatUseCase: SyncChatUseCase,
        updateChatMessageAttachmentsUseCase: UpdateChatMessageAttachmentsUseCase,
        notificationClient: any NotificationClient,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.memberContextStore = memberContextStore
        self.chatRepository = chatRepository
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.fileTransferService = fileTransferService
        self.ocrOrchestrator = ocrOrchestrator
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.syncChatUseCase = syncChatUseCase
        self.updateChatMessageAttachmentsUseCase = updateChatMessageAttachmentsUseCase
        self.notificationClient = notificationClient
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.translateKnowledgeTextUseCase = translateKnowledgeTextUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.saveTypedMedicalDocumentUseCase = saveTypedMedicalDocumentUseCase
        self.logger = logger
    }

    func enqueueComposerAttachments(_ attachments: [ChatComposerAttachmentPreview], for threadID: UUID) {
        guard attachments.isEmpty == false else { return }
        stateStore.appendComposerAttachments(attachments, for: threadID)
        for attachment in attachments {
            startPreparingAttachment(attachment, threadID: threadID)
        }
    }

    func removeComposerAttachment(id: UUID, for threadID: UUID) {
        composerAttachmentTasks[id]?.cancel()
        composerAttachmentTasks[id] = nil
        stateStore.removeComposerAttachment(id: id, for: threadID)
    }

    func downloadChatImageToLocalFile(meta: ChatUploadedImageAttachmentMeta) async throws -> URL {
        let resolvedPath: String
        if let objectKey = meta.objectKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           objectKey.isEmpty == false {
            resolvedPath = try await fileTransferService.makePresignedDownloadURL(objectKey: objectKey).absoluteString
        } else if let remote = meta.remoteURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  remote.isEmpty == false {
            resolvedPath = remote
        } else if let filePath = meta.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  (filePath.hasPrefix("http://") || filePath.hasPrefix("https://")) {
            resolvedPath = filePath
        } else {
            logger.warning("聊天图片下载缺少 object_key/remote_url，fileID=\(meta.fileId)", module: .general)
            throw SparkNetworkError.decoding(
                NSError(
                    domain: "ChatImageDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "图片缺少可下载地址"]
                )
            )
        }
        let managedFile = ManagedFileRecord(
            id: meta.fileId,
            fileUUID: meta.fileUUID,
            filePath: resolvedPath,
            originalName: meta.originalName,
            fileSize: 0,
            mimeType: meta.mimeType,
            fileMd5: meta.fileMd5,
            isPublic: false,
            businessType: ChatSendImageAssembly.chatAttachmentBusinessType,
            businessID: "",
            createdAt: "",
            objectKey: nil,
            storageType: nil
        )
        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            return cached
        }
        logger.debug("聊天图片触发公共下载，fileID=\(meta.fileId)", module: .general)
        return try await fileTransferService.download(file: managedFile)
    }

    private func startPreparingAttachment(_ attachment: ChatComposerAttachmentPreview, threadID: UUID) {
        composerAttachmentTasks[attachment.id]?.cancel()
        stateStore.setComposerPreparedAttachmentState(
            id: attachment.id,
            ChatComposerPreparedAttachmentState(phase: .uploading, progress: 0, prepared: nil, errorMessage: nil)
        )
        composerAttachmentTasks[attachment.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let record = try await self.fileTransferService.upload(
                    ManagedFileUploadPayload(
                        data: attachment.imageData,
                        fileName: attachment.displayName,
                        businessType: ChatSendImageAssembly.chatAttachmentBusinessType,
                        businessID: attachment.id.uuidString,
                        isPublic: false,
                        onUploadProgress: { progress in
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                self.stateStore.setComposerAttachmentUploadProgress(id: attachment.id, progress: progress)
                                var state = self.stateStore.composerPreparedAttachmentState(id: attachment.id) ?? .pending
                                state.phase = .uploading
                                state.progress = progress
                                state.errorMessage = nil
                                self.stateStore.setComposerPreparedAttachmentState(id: attachment.id, state)
                            }
                        }
                    )
                )
                await MainActor.run {
                    var state = self.stateStore.composerPreparedAttachmentState(id: attachment.id) ?? .pending
                    state.phase = .ocring
                    state.progress = 1
                    state.errorMessage = nil
                    self.stateStore.setComposerPreparedAttachmentState(id: attachment.id, state)
                }
                let ocrResult = try await self.ocrOrchestrator.recognize(
                    imageData: attachment.imageData,
                    options: .fastPreview
                )
                await MainActor.run {
                    let prepared = ChatPreparedImageAttachment(
                        previewID: attachment.id,
                        record: record,
                        ocrText: ocrResult.text
                    )
                    let state = ChatComposerPreparedAttachmentState(
                        phase: .success,
                        progress: 1,
                        prepared: prepared,
                        errorMessage: nil
                    )
                    self.stateStore.setComposerPreparedAttachmentState(id: attachment.id, state)
                    self.stateStore.setComposerAttachmentUploadProgress(id: attachment.id, progress: 1)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.stateStore.removeComposerPreparedAttachmentState(id: attachment.id)
                    self.stateStore.setComposerAttachmentUploadProgress(id: attachment.id, progress: 0)
                }
            } catch {
                await MainActor.run {
                    let state = ChatComposerPreparedAttachmentState(
                        phase: .failed,
                        progress: 0,
                        prepared: nil,
                        errorMessage: error.localizedDescription
                    )
                    self.stateStore.setComposerPreparedAttachmentState(id: attachment.id, state)
                    self.stateStore.setComposerAttachmentUploadProgress(id: attachment.id, progress: 0)
                }
            }
            await MainActor.run {
                self.composerAttachmentTasks[attachment.id] = nil
            }
        }
    }

    func refreshChatModelPicker() async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let models = snapshot.allModels
            .filter { model in
                model.isHidden == false &&
                model.supportsText &&
                snapshot.shouldOfferTrialModelInChatPicker(modelName: model.name) &&
                canUseInChatPicker(model: model, snapshot: snapshot)
            }
            .sorted { $0.position < $1.position }

        let options = models.map { model in
            ChatComposerModelOption(
                modelName: model.name,
                title: model.displayName,
                iconSystemName: model.identity == .agent
                    ? (model.iconSymbol?.isEmpty == false ? model.iconSymbol! : "person.crop.circle")
                    : "cpu"
            )
        }
        chatScenarioModels = options
    }

    func refreshReasoningToolbarContext(for threadID: UUID) async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let name = await MainActor.run {
            stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName
        }
        let ctx = snapshot.chatReasoningContext(selectedModelName: name)
        let mm = snapshot.chatMultimodalCapabilities(selectedModelName: name)
        await MainActor.run {
            reasoningToolbarContext = ctx
            currentModelSupportsMultimodal = mm.supportsMultimodal
        }
    }

    /// 刷新会话级图片送达方式展示（依赖线程列表中的 `ChatThread`）。
    func refreshThreadImageDeliveryMode(for threadID: UUID) async {
        let fromList = await MainActor.run {
            stateStore.threadItems.first(where: { $0.id == threadID })?.thread
        }
        if let thread = fromList {
            await MainActor.run {
                threadImageDeliveryMode = thread.imageDeliveryMode
            }
            return
        }
        if let thread = await chatRepository.loadThread(id: threadID) {
            await MainActor.run {
                threadImageDeliveryMode = thread.imageDeliveryMode
            }
        }
    }

    func setThreadImageDeliveryMode(_ mode: ChatThreadImageDeliveryMode, for threadID: UUID) async {
        await chatRepository.updateThreadImageDeliveryMode(threadID: threadID, imageDeliveryModeRaw: mode.rawValue)
        let items = await loadChatThreadsUseCase.execute()
        await MainActor.run {
            stateStore.setThreads(items)
            threadImageDeliveryMode = mode
        }
    }

    private func applyChatModelRuntimeOverride(selectedName: String?) async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        guard let name = selectedName, name.isEmpty == false else {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            return
        }

        if let selected = snapshot.allModels.first(where: { $0.name == name }) {
            if selected.company.uppercased() == LocalModelService.localCompany {
                await aiConfigCenter.setRuntimeOverride(
                    AIScenarioConfig(
                        endpoint: "local://chat/completions",
                        model: selected.name,
                        apiKey: nil,
                        temperature: snapshot.chat.temperature,
                        maxTokens: snapshot.chat.maxTokens
                    ),
                    for: .chat
                )
                return
            }

            if selected.identity == .agent,
               let baseModelName = selected.baseModelName,
               let base = snapshot.allModels.first(where: { $0.name == baseModelName }) {
                let endpoint = endpointForModelCompany(base.company, snapshot: snapshot) ?? snapshot.chat.endpoint
                let apiKey = apiKeyForModelCompany(base.company, snapshot: snapshot)
                await aiConfigCenter.setRuntimeOverride(
                    AIScenarioConfig(
                        endpoint: endpoint,
                        model: base.name,
                        apiKey: apiKey,
                        temperature: snapshot.chat.temperature,
                        maxTokens: snapshot.chat.maxTokens
                    ),
                    for: .chat
                )
                return
            }

            let endpoint = endpointForModelCompany(selected.company, snapshot: snapshot) ?? snapshot.chat.endpoint
            let apiKey = apiKeyForModelCompany(selected.company, snapshot: snapshot)
            await aiConfigCenter.setRuntimeOverride(
                AIScenarioConfig(
                    endpoint: endpoint,
                    model: selected.name,
                    apiKey: apiKey,
                    temperature: snapshot.chat.temperature,
                    maxTokens: snapshot.chat.maxTokens
                ),
                for: .chat
            )
            return
        }

        if let bundle = snapshot.scenarioRemoteBundles?.chat,
           let row = bundle.models.first(where: { $0.model == name }) {
            await aiConfigCenter.setRuntimeOverride(row.asScenarioConfig(), for: .chat)
            return
        }

        await aiConfigCenter.clearRuntimeOverride(for: .chat)
    }

    private func endpointForModelCompany(_ company: String, snapshot: AISettingsSnapshot) -> String? {
        snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })?.requestURL
    }

    private func apiKeyForModelCompany(_ company: String, snapshot: AISettingsSnapshot) -> String? {
        let raw = snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })?.key ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func canUseInChatPicker(model: AllModels, snapshot: AISettingsSnapshot) -> Bool {
        let localCompany = LocalModelService.localCompany.uppercased()
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if company == localCompany {
            return true
        }

        let provider = snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company
        })
        guard let provider else { return false }
        return provider.isHidden == false &&
        provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func loadMessagesIfNeeded(for threadID: UUID) async {
        let total = await loadChatMessagesUseCase.count(threadID: threadID)
        let messages = await loadChatMessagesUseCase.execute(
            threadID: threadID,
            limit: MessagePagingConfig.initialLimit,
            before: nil
        )
        let hasMore = total > messages.count
        stateStore.setMessages(messages, for: threadID, hasMore: hasMore)

        // 本地优先展示，再异步做远端增量同步，避免进入会话瞬时 UI 抖动。
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.syncChatUseCase.syncThreadOnOpen(threadID: threadID)
                let latestTotal = await self.loadChatMessagesUseCase.count(threadID: threadID)
                let latestMessages = await self.loadChatMessagesUseCase.execute(
                    threadID: threadID,
                    limit: MessagePagingConfig.initialLimit,
                    before: nil
                )
                let latestHasMore = latestTotal > latestMessages.count
                await MainActor.run {
                    self.stateStore.setMessages(latestMessages, for: threadID, hasMore: latestHasMore)
                }
            } catch {
                await MainActor.run {
                    self.stateStore.setError(error.localizedDescription)
                }
                self.logger.warning("会话打开同步失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    func loadMoreMessages(for threadID: UUID) async {
        guard stateStore.hasMoreMessages(for: threadID) else { return }
        guard stateStore.isLoadingMoreMessages(for: threadID) == false else { return }
        guard let oldest = stateStore.selectedMessages.first?.createdAt else { return }

        stateStore.setLoadingMore(true, for: threadID)
        defer { stateStore.setLoadingMore(false, for: threadID) }

        let older = await loadChatMessagesUseCase.execute(
            threadID: threadID,
            limit: MessagePagingConfig.loadMoreLimit,
            before: oldest
        )
        let hasMore = older.count >= MessagePagingConfig.loadMoreLimit
        stateStore.prependMessages(older, for: threadID, hasMore: hasMore)
    }

    func sendCurrentDraft() async {
        guard stateStore.isSending == false else { return }
        guard let threadID = stateStore.selectedThreadID else { return }

        let composer = stateStore.composerDraft(for: threadID)
        guard composer.hasVisualContent else { return }
        guard stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false else { return }

        let draft = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let flags = composer.runtimeFlags
        let inference = ChatOrchestratorInferenceOptions(
            useTools: flags.useTools,
            useKnowledgeBag: flags.useKnowledgeBag,
            useWebSearch: flags.useWebSearch,
            reasoningEnabled: flags.reasoningEnabled,
            reasoningEffortTier: flags.reasoningEffortTier
        )

        logger.info(
            "发送对话开始，thread=\(shortID(threadID)), member=\(shortID(memberContextStore.context.selectedMemberID)), textLen=\(draft.count), attachments=\(composer.attachments.count)",
            module: .general
        )
        stateStore.setSending(true)
        defer { stateStore.setSending(false) }

        do {
            await applyChatModelRuntimeOverride(selectedName: flags.selectedChatModelName)
            let modelReasoning = await aiSettingsRepository.loadSnapshot()
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName)
            let streamingMessageID = UUID()
            let stateStore = self.stateStore
            stateStore.clearComposerAttachmentUploadProgress()
            stateStore.startStreamingAssistant(
                threadID: threadID,
                clientMessageID: streamingMessageID,
                kind: .text
            )
            let loadChatThreadsUseCase = self.loadChatThreadsUseCase
            let snapshot = try await sendMessageUseCase.execute(
                threadID: threadID,
                memberID: memberContextStore.context.selectedMemberID,
                userInput: composer.text,
                composerAttachments: composer.attachments,
                preparedImageAttachments: stateStore.preparedImageAttachments(for: threadID),
                selectedChatModelName: flags.selectedChatModelName,
                assistantClientMessageID: streamingMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                onImageUploadProgress: { id, progress in
                    Task { @MainActor in
                        stateStore.setComposerAttachmentUploadProgress(id: id, progress: progress)
                    }
                },
                onUserMessagePersisted: { localSnapshot in
                    let threadItems = await loadChatThreadsUseCase.execute()
                    await MainActor.run {
                        stateStore.setSelectedThreadID(localSnapshot.thread.id)
                        // 保留流式占位：setMessages 默认会清空 streamingAssistants，会导致后续 onAssistantPartial 全部失效。
                        stateStore.setMessages(localSnapshot.messages, for: localSnapshot.thread.id, clearStreamingAssistant: false)
                        stateStore.setThreads(threadItems)
                        stateStore.clearDraft(for: localSnapshot.thread.id)
                    }
                },
                onAssistantPartial: { delta in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(threadID: threadID, delta: delta)
                    }
                }
            )
            let finalItems = await loadChatThreadsUseCase.execute()
            stateStore.setThreads(finalItems)
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.clearDraft(for: snapshot.thread.id)
            stateStore.setError(nil)
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
        } catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(error.localizedDescription)
            logger.error("发送对话失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.send")
        }
    }

    func retryFailedMessage(clientMessageID: UUID) async {
        logger.info("重试失败消息开始，clientMessageID=\(shortID(clientMessageID))", module: .general)
        do {
            try await retryFailedMessageUseCase.execute(clientMessageID: clientMessageID)
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.info("重试失败消息完成，clientMessageID=\(shortID(clientMessageID))", module: .general)
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("重试失败消息失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    func sync() async {
        logger.debug("手动聊天同步开始", module: .general)
        do {
            try await syncChatUseCase.execute()
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.debug("手动聊天同步完成", module: .general)
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("手动聊天同步失败：\(error.localizedDescription)", module: .general)
        }
    }

    func chatPageDidAppear() async {
        guard isRealtimeActive == false else { return }
        isRealtimeActive = true
        await syncChatUseCase.startRealtime()
    }

    func chatPageDidDisappear() async {
        guard isRealtimeActive else { return }
        isRealtimeActive = false
        await syncChatUseCase.stopRealtime()
    }

    func translateMessageText(_ text: String) async throws -> String {
        try await translateKnowledgeTextUseCase.execute(text: text)
    }

    func saveMessageAsKnowledge(content: String, suggestedTitle: String?) async throws -> KnowledgeDocument {
        let fallback = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        let title = (suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? suggestedTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (fallback.isEmpty ? "聊天知识" : fallback)
        logger.info("保存消息为知识开始，title=\(title)", module: .general)
        // 兼容旧入口：直接将整条消息保存为知识文档。
        return try await createKnowledgeDocumentUseCase.execute(
            KnowledgeDocumentDraft(
                title: title,
                content: content,
                source: .tool
            )
        )
    }

    /// 保存消息内“已生成的知识卡”，用于卡片预览后的显式确认保存。
    func saveKnowledgeCard(title: String, content: String) async throws -> KnowledgeDocument {
        // 标题兜底策略：
        // 1) 优先使用卡片标题；
        // 2) 标题为空时，用正文前缀；
        // 3) 仍为空时，使用默认标题。
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        let resolvedTitle = trimmedTitle.isEmpty ? (fallback.isEmpty ? "聊天知识" : fallback) : trimmedTitle
        logger.info("保存知识卡开始，title=\(resolvedTitle)", module: .general)
        do {
            let document = try await createKnowledgeDocumentUseCase.execute(
                KnowledgeDocumentDraft(
                    title: resolvedTitle,
                    content: content,
                    source: .tool
                )
            )
            logger.info("保存知识卡完成，title=\(resolvedTitle)", module: .general)
            // 成功后统一给轻提示，确保用户知道“已入库”。
            notificationClient.success(
                L10n.text("chat.bubble.knowledge.saved.toast"),
                title: nil,
                source: "chat.knowledge.save"
            )
            return document
        } catch {
            // 失败路径保留错误提示与日志，便于后续定位落库问题。
            logger.error("保存知识卡失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("common.error"),
                source: "chat.knowledge.save"
            )
            throw error
        }
    }

    func updateTaskCardStatus(
        threadID: UUID,
        message: ChatMessage,
        cardID: Int,
        status: TaskCard.CardStatus
    ) async {
        guard let updatedAttachments = replacingTaskCardStatus(
            in: message.attachments,
            cardID: cardID,
            status: status
        ) else { return }

        await updateChatMessageAttachmentsUseCase.execute(
            clientMessageID: message.clientMessageID,
            attachments: updatedAttachments,
            markPendingForSync: true
        )

        stateStore.updateMessageAttachments(
            threadID: threadID,
            clientMessageID: message.clientMessageID,
            attachments: updatedAttachments
        )

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("任务卡状态上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    private func replacingTaskCardStatus(
        in attachments: [ChatAttachment],
        cardID: Int,
        status: TaskCard.CardStatus
    ) -> [ChatAttachment]? {
        guard let index = attachments.firstIndex(where: { $0.type == ChatStreamFieldKey.taskCards }),
              let raw = attachments[index].text,
              let data = raw.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var cards = try? decoder.decode([TaskCard].self, from: data) else { return nil }
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardID }) else { return nil }
        cards[cardIndex].status = status
        cards[cardIndex].updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(cards),
              let text = String(data: encoded, encoding: .utf8) else {
            return nil
        }
        var next = attachments
        next[index] = ChatAttachment(
            id: attachments[index].id,
            type: attachments[index].type,
            url: attachments[index].url,
            text: text
        )
        return next
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    // MARK: - 对话内结构化医疗卡片保存

    func saveMedicationStructuredCard(threadID: UUID, message: ChatMessage, card: MedicationChatCardPayload) async {
        guard let data = card.draftJSON.data(using: .utf8),
              let draft = try? JSONDecoder().decode(MedicationRecognitionDraft.self, from: data) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return
        }
        guard let memberID = resolvedMemberID(fallback: card.memberID) else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.medical.save")
            return
        }
        await saveWithCardId(card.id, rawTrace: card.displayName) {
            let envelope = MedicalDocumentRecognitionEnvelope(
                memberID: memberID,
                sourceFiles: [],
                rawOCRText: card.displayName,
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .medication,
                    confidence: 1,
                    source: .manual,
                    reason: "chat_save"
                )
            )
            return MedicalDocumentTypedExtractionOutput(
                envelope: envelope,
                typedResult: .medication([draft]),
                extractedJSON: card.draftJSON,
                payloadPreview: ""
            )
        } onSuccess: {
            await markMedicationSaved(threadID: threadID, message: message, cardID: card.id)
        }
    }

    func savePrescriptionStructuredCard(threadID: UUID, message: ChatMessage, card: PrescriptionChatCardPayload) async {
        guard let data = card.draftJSON.data(using: .utf8),
              let draft = try? JSONDecoder().decode(PrescriptionRecognitionDraft.self, from: data) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return
        }
        guard let memberID = resolvedMemberID(fallback: card.memberID) else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.medical.save")
            return
        }
        await saveWithCardId(card.id, rawTrace: card.title) {
            let envelope = MedicalDocumentRecognitionEnvelope(
                memberID: memberID,
                sourceFiles: [],
                rawOCRText: card.title,
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .prescription,
                    confidence: 1,
                    source: .manual,
                    reason: "chat_save"
                )
            )
            return MedicalDocumentTypedExtractionOutput(
                envelope: envelope,
                typedResult: .prescription(draft),
                extractedJSON: card.draftJSON,
                payloadPreview: ""
            )
        } onSuccess: {
            await markPrescriptionSaved(threadID: threadID, message: message, cardID: card.id)
        }
    }

    func saveExamReportStructuredCard(threadID: UUID, message: ChatMessage, card: ExamReportChatCardPayload) async {
        guard let data = card.draftJSON.data(using: .utf8) else { return }
        guard let memberID = resolvedMemberID(fallback: card.memberID) else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.medical.save")
            return
        }
        if let report = try? JSONDecoder().decode(MedicalReportRecognitionDraft.self, from: data) {
            await saveWithCardId(card.id, rawTrace: card.title) {
                let envelope = MedicalDocumentRecognitionEnvelope(
                    memberID: memberID,
                    sourceFiles: [],
                    rawOCRText: card.title,
                    typeResolution: MedicalDocumentTypeResolution(
                        kind: .medicalReport,
                        confidence: 1,
                        source: .manual,
                        reason: "chat_save"
                    )
                )
                return MedicalDocumentTypedExtractionOutput(
                    envelope: envelope,
                    typedResult: .medicalReport([report]),
                    extractedJSON: card.draftJSON,
                    payloadPreview: ""
                )
            } onSuccess: {
                await markExamReportSaved(threadID: threadID, message: message, cardID: card.id)
            }
            return
        }
        if let health = try? JSONDecoder().decode(HealthExamRecognitionDraft.self, from: data) {
            await saveWithCardId(card.id, rawTrace: card.title) {
                let envelope = MedicalDocumentRecognitionEnvelope(
                    memberID: memberID,
                    sourceFiles: [],
                    rawOCRText: card.title,
                    typeResolution: MedicalDocumentTypeResolution(
                        kind: .healthExamReport,
                        confidence: 1,
                        source: .manual,
                        reason: "chat_save"
                    )
                )
                return MedicalDocumentTypedExtractionOutput(
                    envelope: envelope,
                    typedResult: .healthExamReport(health),
                    extractedJSON: card.draftJSON,
                    payloadPreview: ""
                )
            } onSuccess: {
                await markExamReportSaved(threadID: threadID, message: message, cardID: card.id)
            }
        }
    }

    func saveMedicalCaseStructuredCard(threadID: UUID, message: ChatMessage, card: MedicalCaseChatCardPayload) async {
        guard let data = card.draftJSON.data(using: .utf8),
              let draft = try? JSONDecoder().decode(CaseRecognitionDraft.self, from: data) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return
        }
        guard let memberID = resolvedMemberID(fallback: card.memberID) else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.medical.save")
            return
        }
        await saveWithCardId(card.id, rawTrace: card.title) {
            let envelope = MedicalDocumentRecognitionEnvelope(
                memberID: memberID,
                sourceFiles: [],
                rawOCRText: card.title,
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .caseDocument,
                    confidence: 1,
                    source: .manual,
                    reason: "chat_save"
                )
            )
            return MedicalDocumentTypedExtractionOutput(
                envelope: envelope,
                typedResult: .caseDocument(draft),
                extractedJSON: card.draftJSON,
                payloadPreview: ""
            )
        } onSuccess: {
            await markMedicalCaseSaved(threadID: threadID, message: message, cardID: card.id)
        }
    }

    private func saveWithCardId(
        _ cardID: UUID,
        rawTrace: String,
        buildOutput: () throws -> MedicalDocumentTypedExtractionOutput,
        onSuccess: () async -> Void
    ) async {
        savingStructuredHealthCardIDs.insert(cardID)
        defer { savingStructuredHealthCardIDs.remove(cardID) }
        do {
            let output = try buildOutput()
            _ = try await saveTypedMedicalDocumentUseCase.execute(output: output)
            notificationClient.success(
                L10n.text("chat.medical_card.saved.toast"),
                title: nil,
                source: "chat.medical.save"
            )
            logger.info("对话医疗卡片已保存 trace=\(rawTrace)", module: .general)
            await onSuccess()
        } catch {
            logger.error("对话医疗卡片保存失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.medical.save")
        }
    }

    private func resolvedMemberID(fallback: Int) -> Int? {
        if let id = memberContextStore.context.selectedMemberID {
            return id
        }
        return fallback > 0 ? fallback : nil
    }

    private func markMedicationSaved(threadID: UUID, message: ChatMessage, cardID: UUID) async {
        guard let updated = replacingStructuredHealthCardsBlob(in: message.attachments, mutate: { $0.markMedicationSaved(id: cardID) }) else { return }
        await persistStructuredAttachments(threadID: threadID, message: message, attachments: updated)
    }

    private func markPrescriptionSaved(threadID: UUID, message: ChatMessage, cardID: UUID) async {
        guard let updated = replacingStructuredHealthCardsBlob(in: message.attachments, mutate: { $0.markPrescriptionSaved(id: cardID) }) else { return }
        await persistStructuredAttachments(threadID: threadID, message: message, attachments: updated)
    }

    private func markExamReportSaved(threadID: UUID, message: ChatMessage, cardID: UUID) async {
        guard let updated = replacingStructuredHealthCardsBlob(in: message.attachments, mutate: { $0.markExamReportSaved(id: cardID) }) else { return }
        await persistStructuredAttachments(threadID: threadID, message: message, attachments: updated)
    }

    private func markMedicalCaseSaved(threadID: UUID, message: ChatMessage, cardID: UUID) async {
        guard let updated = replacingStructuredHealthCardsBlob(in: message.attachments, mutate: { $0.markMedicalCaseSaved(id: cardID) }) else { return }
        await persistStructuredAttachments(threadID: threadID, message: message, attachments: updated)
    }

    private func persistStructuredAttachments(threadID: UUID, message: ChatMessage, attachments: [ChatAttachment]) async {
        await updateChatMessageAttachmentsUseCase.execute(
            clientMessageID: message.clientMessageID,
            attachments: attachments,
            markPendingForSync: true
        )
        stateStore.updateMessageAttachments(
            threadID: threadID,
            clientMessageID: message.clientMessageID,
            attachments: attachments
        )
        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("医疗卡片状态上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    private func replacingStructuredHealthCardsBlob(
        in attachments: [ChatAttachment],
        mutate: (inout StructuredHealthCardsBlob) -> Void
    ) -> [ChatAttachment]? {
        guard let index = attachments.firstIndex(where: { $0.type == ChatStreamFieldKey.structuredHealthCards }),
              let raw = attachments[index].text,
              let data = raw.data(using: .utf8),
              var blob = try? JSONDecoder().decode(StructuredHealthCardsBlob.self, from: data) else {
            return nil
        }
        mutate(&blob)
        let enc = JSONEncoder()
        guard let outData = try? enc.encode(blob),
              let text = String(data: outData, encoding: .utf8) else {
            return nil
        }
        var next = attachments
        next[index] = ChatAttachment(
            id: attachments[index].id,
            type: attachments[index].type,
            url: attachments[index].url,
            text: text
        )
        return next
    }
}
