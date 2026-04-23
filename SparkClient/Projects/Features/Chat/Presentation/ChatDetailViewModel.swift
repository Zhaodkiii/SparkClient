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
    private let stateStore: ChatStateStore
    private let memberContextStore: MemberContextStore
    private let chatRepository: any ChatRepository
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let fileTransferService: FileTransferService
    private let ocrOrchestrator: OCROrchestrator
    private let ocrDocumentExtractor: OCRDocumentExtractor
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
    private var currentGenerationTask: Task<Void, Never>?
    private var currentGenerationCancellationToken: AIRuntimeCancellationToken?
    private var cancellationNoticeThreadIDs: Set<UUID> = []
    private var finalizedInterruptedAssistantMessageIDs: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private let chatLoadCoordinator = ChatLoadCoordinator()

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
        ocrDocumentExtractor: OCRDocumentExtractor,
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
        self.ocrDocumentExtractor = ocrDocumentExtractor
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

        NotificationCenter.default.publisher(for: .sparkChatDatabaseDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let threadID = self.stateStore.selectedThreadID else { return }
                if let event = note.chatConversationChangeEvent {
                    if let changedThreadID = event.threadID, changedThreadID != threadID {
                        return
                    }
                    switch event.kind {
                    case .messagesAppended:
                        let currentIDs = Set(self.stateStore.persistedMessages(for: threadID).map(\.clientMessageID))
                        if event.affectedClientMessageIDs.allSatisfy(currentIDs.contains) {
                            return
                        }
                    case .threadsChanged:
                        return
                    case .messagesUpdated, .messagesMerged:
                        break
                    }
                }
                let streaming = self.stateStore.isStreamingAssistantActive(for: threadID)
                let delay: UInt64 = streaming ? 220 : 120
                self.chatLoadCoordinator.schedule(delayMs: delay) { [weak self] in
                    guard let self else { return }
                    await self.loadMessagesIfNeeded(for: threadID, skipRemoteSync: true)
                }
            }
            .store(in: &cancellables)
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

    func cachedLocalURLForChatAttachment(_ attachment: ChatAttachment) async -> URL? {
        let managedFile = Self.managedFileRecord(for: attachment)
        return await fileTransferService.cachedURL(file: managedFile)
    }

    func downloadChatAttachmentToLocalFile(attachment: ChatAttachment) async throws -> URL {
        let dedupeKey = attachment.imageDownloadDedupeKey
        let fts = fileTransferService
        let log = logger
        return try await ChatImageDownloadCoordinator.shared.cachedOrDownload(dedupeKey: dedupeKey) {
            try await ChatAttachmentFileDownload.downloadToLocalFile(
                attachment: attachment,
                fileTransferService: fts,
                logger: log
            )
        }
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
                        data: attachment.data,
                        fileName: attachment.displayName,
                        businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
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
                let ocrResult: OCRRecognition
                if attachment.kind == .image {
                    ocrResult = try await self.ocrOrchestrator.recognize(
                        imageData: attachment.data,
                        options: .fastPreview
                    )
                } else {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("chat-document-\(attachment.id.uuidString)-\(attachment.displayName)")
                    try attachment.data.write(to: tempURL, options: [.atomic])
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    ocrResult = try await self.ocrDocumentExtractor.extractText(
                        from: tempURL,
                        orchestrator: self.ocrOrchestrator,
                        options: .fastPreview
                    )
                }
                await MainActor.run {
                    let prepared = ChatPreparedAttachment(
                        previewID: attachment.id,
                        kind: attachment.kind,
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
    /// 刷新输入栏模型选择器列表
    /// 并返回当前线程/场景下的推荐初始模型名（用于首次进入会话时恢复选中状态）
    /// 列表数据源与校验规则：以客户端 + 服务端 Pro 合并后的场景模型 effectiveScenarioBundles().chat.models 为准
    /// 不经过本地目录/试用模型筛选
    func refreshChatModelPicker(for threadID: UUID) async -> String? {
        // 获取生效的场景模型配置，获取失败则清空模型列表并返回 nil
        guard let bundles = try? await aiConfigCenter.effectiveScenarioBundles() else {
            chatScenarioModels = []
            return nil
        }
        
        // 提取聊天场景可用模型列表
        let rows = bundles.chat.models
        
        // 转换为界面展示用的模型选项（处理名称、图标）
        chatScenarioModels = rows.map { row in
            // 处理模型显示名称：去除首尾空白，为空则使用原始模型名
            let trimmedTitle = row.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? row.name : trimmedTitle
            
            // 处理模型图标：去除首尾空白
            let trimmedIcon = row.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let icon: String
            
            // 图标优先级：配置图标 > 智能代理图标 > 默认CPU图标
            if trimmedIcon.isEmpty == false {
                icon = trimmedIcon
            } else {
                icon = row.identity == AIModelIdentity.agent.rawValue ? "person.crop.circle" : "cpu"
            }
            
            // 构建界面选项模型
            return ChatComposerModelOption(
                modelName: row.name,     // 原始模型唯一标识
                title: title,            // 界面显示名称
                iconSystemName: icon     // 系统图标名称
            )
        }

        // 校验并修正当前选中的模型（确保在可选列表内）
        await validateCurrentSelection(for: threadID)

        // 提取当前可选模型名称集合，为空则直接返回 nil
        let namesInPicker = Set(chatScenarioModels.map(\.modelName))
        guard namesInPicker.isEmpty == false else { return nil }

        // 加载当前会话线程，获取线程保存的模型名称
        let thread = await chatRepository.loadThread(id: threadID)
        let trimmedThreadModel = thread?.currentModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let threadModel = trimmedThreadModel.isEmpty ? nil : trimmedThreadModel

        // 优先返回：当前会话保存的有效模型
        if let threadModel, namesInPicker.contains(threadModel) {
            return threadModel
        }
        
        // 其次返回：场景默认模型
        if let defaultName = bundles.resolveRow(for: .chat, preferredModelName: nil)?.name,
           namesInPicker.contains(defaultName) {
            return defaultName
        }
        
        // 最后返回：列表第一个模型
        return chatScenarioModels.first?.modelName
    }

    /// 将所选模型立即写入线程并尝试上送同步（不等待发送消息）。
    func updateThreadModel(_ preferredModelName: String?, for threadID: UUID) async {
        guard let bundles = try? await aiConfigCenter.effectiveScenarioBundles() else { return }

        let trimmedSelected = preferredModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredForResolve = (trimmedSelected?.isEmpty == false) ? trimmedSelected : nil
        guard let row = bundles.resolveRow(for: .chat, preferredModelName: preferredForResolve) else {
            logger.warning("updateThreadModel：无法解析 chat 场景模型，thread=\(shortID(threadID))", module: .general)
            return
        }
        let persistedModelName: String
        if let trimmedSelected, trimmedSelected.isEmpty == false {
            persistedModelName = trimmedSelected
        } else {
            persistedModelName = row.name
        }

        guard let thread = await chatRepository.loadThread(id: threadID) else { return }
        if thread.currentModelName == persistedModelName {
            return
        }

        await chatRepository.updateThreadGenerationConfig(
            threadID: threadID,
            currentModelName: persistedModelName,
            temperature: thread.temperature,
            topP: thread.topP,
            maxTokens: thread.maxTokens,
            maxMessages: thread.maxMessages,
            rolePrompt: thread.rolePrompt
        )

        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            stateStore.upsertThreadListItem(item)
        }

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("线程模型配置上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    /// 当远程模型列表变化时，丢弃已不在可选列表中的选择并回退为场景默认。
    func validateCurrentSelection(for threadID: UUID) async {
        let namesInPicker = Set(chatScenarioModels.map(\.modelName))
        let trimmed = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selected = trimmed.isEmpty ? nil : trimmed
        guard let selected else { return }
        guard namesInPicker.contains(selected) == false else { return }

        stateStore.setSelectedChatModelName(nil, for: threadID)
        await updateThreadModel(nil, for: threadID)
    }

    func refreshReasoningToolbarContext(for threadID: UUID) async {
        let name = await MainActor.run {
            stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName
        }
        guard let bundles = try? await aiConfigCenter.effectiveScenarioBundles() else {
            await MainActor.run {
                reasoningToolbarContext = .unknown
                currentModelSupportsMultimodal = false
            }
            return
        }
        let ctx = bundles.chatReasoningContext(selectedModelName: name)
        let mm = bundles.chatMultimodalCapabilities(selectedModelName: name)
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
        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            await MainActor.run {
                stateStore.upsertThreadListItem(item)
                threadImageDeliveryMode = mode
            }
        } else {
            await MainActor.run {
                threadImageDeliveryMode = mode
            }
        }
    }

    func updateThreadMemberBinding(_ memberID: Int?, for threadID: UUID) async {
        let current = await chatRepository.loadThread(id: threadID)
        guard current?.memberID != memberID else { return }

        logger.info(
            "会话成员档案绑定变更，thread=\(shortID(threadID)), member=\(shortID(memberID))",
            module: .general
        )
        await chatRepository.updateThreadMemberBinding(threadID: threadID, memberID: memberID)

        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            stateStore.upsertThreadListItem(item)
        }

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("会话成员档案绑定上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    func updateThreadGenerationSettings(_ settings: ChatThreadGenerationSettings, for threadID: UUID) async {
        guard let existing = await chatRepository.loadThread(id: threadID) else { return }
        let next = ChatThreadGenerationSettings(
            currentModelName: settings.currentModelName,
            temperature: settings.temperature,
            topP: settings.topP,
            maxTokens: settings.maxTokens,
            maxMessages: settings.maxMessages,
            rolePrompt: settings.rolePrompt,
            imageDeliveryMode: settings.imageDeliveryMode
        )
        let current = ChatThreadGenerationSettings(thread: existing)
        guard current != next else { return }

        await chatRepository.updateThreadGenerationConfig(
            threadID: threadID,
            currentModelName: next.currentModelName,
            temperature: next.temperature,
            topP: next.topP,
            maxTokens: next.maxTokens,
            maxMessages: next.maxMessages,
            rolePrompt: next.rolePrompt
        )
        if existing.imageDeliveryMode != next.imageDeliveryMode {
            await chatRepository.updateThreadImageDeliveryMode(
                threadID: threadID,
                imageDeliveryModeRaw: next.imageDeliveryMode.rawValue
            )
        }

        await MainActor.run {
            stateStore.setSelectedChatModelName(next.currentModelName, for: threadID)
            threadImageDeliveryMode = next.imageDeliveryMode
        }
        await refreshReasoningToolbarContext(for: threadID)

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("线程参数上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    func loadMessagesIfNeeded(
        for threadID: UUID,
        lockBottomViewport: Bool = false,
        skipRemoteSync: Bool = false
    ) async {
        await satisfyLoadRequest(
            .openOrReloadNewest(
                threadID: threadID,
                skipRemoteSync: skipRemoteSync,
                lockBottomViewport: lockBottomViewport
            )
        )
    }

    func loadMoreMessages(for threadID: UUID) async {
        guard stateStore.hasMoreMessages(for: threadID) else { return }
        guard stateStore.isLoadingMoreMessages(for: threadID) == false else { return }
        guard let oldest = stateStore.persistedMessages(for: threadID).first?.createdAt else { return }

        stateStore.setLoadingMore(true, for: threadID)
        defer { stateStore.setLoadingMore(false, for: threadID) }

        await satisfyLoadRequest(.loadOlderPage(threadID: threadID, before: oldest))
    }

    private func satisfyLoadRequest(_ request: ChatLoadRequest) async {
        switch request {
        case .openOrReloadNewest(let threadID, let skipRemoteSync, let lockBottomViewport):
            if lockBottomViewport {
                stateStore.beginBottomViewportLock(for: threadID)
            }
            let windowLimit = ChatMessageWindow.newestFetchLimit(
                persistedCount: stateStore.persistedMessages(for: threadID).count
            )
            let total = await loadChatMessagesUseCase.count(threadID: threadID)
            let messages = await loadChatMessagesUseCase.execute(
                threadID: threadID,
                limit: windowLimit,
                before: nil
            )
            let hasMore = total > messages.count
            stateStore.setMessages(
                messages,
                for: threadID,
                clearStreamingAssistant: skipRemoteSync == false,
                hasMore: hasMore
            )

            guard skipRemoteSync == false else {
                if lockBottomViewport {
                    stateStore.endBottomViewportLock(for: threadID)
                }
                return
            }

            // 本地优先展示，再异步做远端增量同步，避免进入会话瞬时 UI 抖动。
            Task { [weak self] in
                guard let self else { return }
                defer {
                    Task { @MainActor [weak self] in
                        guard let self, lockBottomViewport else { return }
                        self.stateStore.endBottomViewportLock(for: threadID)
                    }
                }
                do {
                    try await self.syncChatUseCase.syncThreadOnOpen(threadID: threadID)
                    let latestWindowLimit = ChatMessageWindow.newestFetchLimit(
                        persistedCount: self.stateStore.persistedMessages(for: threadID).count
                    )
                    let latestTotal = await self.loadChatMessagesUseCase.count(threadID: threadID)
                    let latestMessages = await self.loadChatMessagesUseCase.execute(
                        threadID: threadID,
                        limit: latestWindowLimit,
                        before: nil
                    )
                    let latestHasMore = latestTotal > latestMessages.count
                    await MainActor.run {
                        self.stateStore.setMessages(latestMessages, for: threadID, hasMore: latestHasMore)
                        self.stateStore.setError(nil, for: threadID)
                    }
                } catch {
                    await MainActor.run {
                        self.stateStore.setError(error.localizedDescription, for: threadID)
                    }
                    self.logger.warning("会话打开同步失败：\(error.localizedDescription)", module: .general)
                }
            }

        case .loadOlderPage(let threadID, let before):
            let older = await loadChatMessagesUseCase.execute(
                threadID: threadID,
                limit: ChatMessageWindow.loadOlderPageSize,
                before: before
            )
            let hasMore = older.count >= ChatMessageWindow.loadOlderPageSize
            stateStore.prependMessages(older, for: threadID, hasMore: hasMore)
        }
    }

    func startSendingCurrentDraft() {
        guard currentGenerationTask == nil else { return }
        currentGenerationTask = Task { [weak self] in
            await self?.sendCurrentDraft()
        }
    }

    func cancelCurrentGeneration() {
        guard let threadID = stateStore.selectedThreadID else { return }
        guard stateStore.isSending || currentGenerationCancellationToken != nil || currentGenerationTask != nil else { return }

        logger.info("用户中断 AI 生成，thread=\(shortID(threadID))", module: .general)
        persistInterruptedAssistantIfNeeded(threadID: threadID, source: "chat.cancel.tap")
        currentGenerationCancellationToken?.cancel()
        currentGenerationTask?.cancel()
        stateStore.finishStreamingAssistant(threadID: threadID)
        stateStore.setSending(false)
        stateStore.setError(nil, for: threadID)
        appendCancellationNoticeIfNeeded(threadID: threadID)
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
        let cancellationToken = AIRuntimeCancellationToken()
        currentGenerationCancellationToken = cancellationToken
        let streamingMessageID = UUID()
        cancellationNoticeThreadIDs.remove(threadID)
        finalizedInterruptedAssistantMessageIDs.remove(streamingMessageID)
        stateStore.setSending(true)
        defer {
            stateStore.setSending(false)
            if currentGenerationCancellationToken === cancellationToken {
                currentGenerationCancellationToken = nil
            }
            currentGenerationTask = nil
        }

        do {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            let modelReasoning = (try? await aiConfigCenter.effectiveScenarioBundles())?
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName) ?? .unknown
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
                preparedAttachments: stateStore.preparedAttachments(for: threadID),
                selectedChatModelName: flags.selectedChatModelName,
                assistantClientMessageID: streamingMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                cancellationToken: cancellationToken,
                onImageUploadProgress: { id, progress in
                    Task { @MainActor in
                        stateStore.setComposerAttachmentUploadProgress(id: id, progress: progress)
                    }
                },
                onUserMessagePersisted: { localSnapshot in
                    let listItem = await loadChatThreadsUseCase.execute(threadID: localSnapshot.thread.id)
                    await MainActor.run {
                        stateStore.setSelectedThreadID(localSnapshot.thread.id)
                        // 保留流式占位：setMessages 默认会清空 streamingAssistants，会导致后续 onAssistantPartial 全部失效。
                        stateStore.setMessages(localSnapshot.messages, for: localSnapshot.thread.id, clearStreamingAssistant: false)
                        if let listItem {
                            stateStore.upsertThreadListItem(listItem)
                        }
                        stateStore.clearDraft(for: localSnapshot.thread.id)
                    }
                },
                onAssistantPartial: { delta in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(threadID: threadID, delta: delta)
                    }
                }
            )
            if let finalRow = await loadChatThreadsUseCase.execute(threadID: snapshot.thread.id) {
                stateStore.upsertThreadListItem(finalRow)
            }
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.clearDraft(for: snapshot.thread.id)
            stateStore.setError(nil, for: snapshot.thread.id)
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
        } catch is CancellationError {
            persistInterruptedAssistantIfNeeded(threadID: threadID, source: "chat.cancel.catch")
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            appendCancellationNoticeIfNeeded(threadID: threadID)
            logger.info("发送对话已中断，thread=\(shortID(threadID))", module: .general)
        } catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            appendAssistantErrorMessage(
                threadID: threadID,
                assistantClientMessageID: streamingMessageID,
                error: error
            )
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

    func retryLatestConversationFailure(for threadID: UUID, preferredClientMessageID: UUID? = nil) async {
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
        if let preferredClientMessageID,
           messages.contains(where: { $0.clientMessageID == preferredClientMessageID && $0.deliveryState == .failed && $0.role == .user }) {
            await retryFailedMessage(clientMessageID: preferredClientMessageID)
            return
        }
        if let latestFailed = messages.last(where: { $0.deliveryState == .failed && $0.role == .user }) {
            await retryFailedMessage(clientMessageID: latestFailed.clientMessageID)
            return
        }
        await regenerateLatestAssistantReply(for: threadID)
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

    func regenerateLatestAssistantReply(for threadID: UUID) async {
        guard stateStore.isSending == false else { return }

        let flags = stateStore.composerDraft(for: threadID).runtimeFlags
        let inference = ChatOrchestratorInferenceOptions(
            useTools: flags.useTools,
            useKnowledgeBag: flags.useKnowledgeBag,
            useWebSearch: flags.useWebSearch,
            reasoningEnabled: flags.reasoningEnabled,
            reasoningEffortTier: flags.reasoningEffortTier
        )

        let cancellationToken = AIRuntimeCancellationToken()
        currentGenerationCancellationToken = cancellationToken
        let streamingMessageID = UUID()
        cancellationNoticeThreadIDs.remove(threadID)
        finalizedInterruptedAssistantMessageIDs.remove(streamingMessageID)
        stateStore.setSending(true)
        defer {
            stateStore.setSending(false)
            if currentGenerationCancellationToken === cancellationToken {
                currentGenerationCancellationToken = nil
            }
            currentGenerationTask = nil
        }

        do {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            let modelReasoning = (try? await aiConfigCenter.effectiveScenarioBundles())?
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName) ?? .unknown
            stateStore.setError(nil, for: threadID)
            stateStore.startStreamingAssistant(
                threadID: threadID,
                clientMessageID: streamingMessageID,
                kind: .text
            )

            let snapshot = try await sendMessageUseCase.executeRegenerateReply(
                threadID: threadID,
                memberID: memberContextStore.context.selectedMemberID,
                selectedChatModelName: flags.selectedChatModelName,
                assistantClientMessageID: streamingMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                cancellationToken: cancellationToken,
                onAssistantPartial: { delta in
                    await MainActor.run {
                        self.stateStore.updateStreamingAssistant(threadID: threadID, delta: delta)
                    }
                }
            )

            if let finalRow = await loadChatThreadsUseCase.execute(threadID: snapshot.thread.id) {
                stateStore.upsertThreadListItem(finalRow)
            }
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.setError(nil, for: snapshot.thread.id)
            logger.info(
                "重新生成回答完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
        } catch is CancellationError {
            persistInterruptedAssistantIfNeeded(threadID: threadID, source: "chat.regenerate.cancel.catch")
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            appendCancellationNoticeIfNeeded(threadID: threadID)
            logger.info("重新生成回答已中断，thread=\(shortID(threadID))", module: .general)
        } catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            appendAssistantErrorMessage(
                threadID: threadID,
                assistantClientMessageID: streamingMessageID,
                error: error
            )
            logger.error("重新生成回答失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    private func appendCancellationNoticeIfNeeded(threadID: UUID) {
        guard cancellationNoticeThreadIDs.contains(threadID) == false else { return }
        cancellationNoticeThreadIDs.insert(threadID)
        appendLocalMessage(
            threadID: threadID,
            role: .system,
            kind: .system,
            content: L10n.text("chat.generation.interrupted"),
            deliveryState: .pending,
            source: "chat.cancel"
        )
    }

    @discardableResult
    private func persistInterruptedAssistantIfNeeded(threadID: UUID, source: String) -> Bool {
        guard let streaming = stateStore.activeStreamingAssistantMessage(for: threadID) else {
            logger.debug("中断固化跳过：无流式助手消息，source=\(source), thread=\(shortID(threadID))", module: .general)
            return false
        }

        let content = streaming.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = streaming.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false || reasoning?.isEmpty == false || streaming.attachments.isEmpty == false else {
            logger.debug("中断固化跳过：已生成内容为空，source=\(source), thread=\(shortID(threadID))", module: .general)
            return false
        }

        guard finalizedInterruptedAssistantMessageIDs.insert(streaming.clientMessageID).inserted else {
            logger.debug("中断固化跳过：assistant 已固化，source=\(source), clientMessageID=\(shortID(streaming.clientMessageID))", module: .general)
            return false
        }

        let finalized = ChatMessage(
            id: streaming.id,
            threadID: threadID,
            role: .assistant,
            kind: streaming.kind,
            content: streaming.content,
            attachments: streaming.attachments,
            reasoningContent: reasoning.flatMap { $0.isEmpty ? nil : $0 },
            reasoningDurationMs: streaming.reasoningDurationMs,
            reasoningExpanded: false,
            reasoningVisibility: streaming.reasoningVisibility,
            clientMessageID: streaming.clientMessageID,
            serverMessageID: nil,
            deliveryState: .pending,
            createdAt: streaming.createdAt,
            serverUpdatedAt: nil,
            isTombstone: false
        )

        var messages = stateStore.persistedMessages(for: threadID)
        if messages.contains(where: { $0.clientMessageID == finalized.clientMessageID }) == false {
            messages.append(finalized)
            stateStore.setMessages(messages, for: threadID, clearStreamingAssistant: false)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.chatRepository.appendMessage(
                    threadID: threadID,
                    role: .assistant,
                    kind: finalized.kind,
                    content: finalized.content,
                    attachments: finalized.attachments,
                    reasoningContent: finalized.reasoningContent,
                    reasoningDurationMs: finalized.reasoningDurationMs,
                    reasoningExpanded: finalized.reasoningExpanded,
                    reasoningVisibility: finalized.reasoningVisibility,
                    clientMessageID: finalized.clientMessageID,
                    serverMessageID: nil,
                    deliveryState: .pending
                )
                await self.sendMessageUseCase.pushPendingMessages(source: source)
                let latest = await self.loadChatMessagesUseCase.execute(threadID: threadID)
                await MainActor.run {
                    self.stateStore.setMessages(latest, for: threadID)
                }
                self.logger.info(
                    "中断时已固化 AI 已生成内容，source=\(source), thread=\(self.shortID(threadID)), clientMessageID=\(self.shortID(finalized.clientMessageID)), contentLength=\(finalized.content.count)",
                    module: .general
                )
            } catch {
                self.logger.error(
                    "中断时固化 AI 已生成内容失败，source=\(source), thread=\(self.shortID(threadID)), error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }

        logger.info(
            "中断时保留 AI 已生成内容到本地列表，source=\(source), thread=\(shortID(threadID)), clientMessageID=\(shortID(finalized.clientMessageID)), contentLength=\(finalized.content.count)",
            module: .general
        )
        return true
    }

    private func appendAssistantErrorMessage(
        threadID: UUID,
        assistantClientMessageID: UUID,
        error: Error
    ) {
        let message = String(
            format: L10n.text("chat.error.response_format"),
            locale: Locale.current,
            error.localizedDescription
        )
        appendLocalMessage(
            threadID: threadID,
            role: .assistant,
            kind: .system,
            content: message,
            deliveryState: .failed,
            clientMessageID: assistantClientMessageID,
            source: "chat.error"
        )
    }

    private func appendLocalMessage(
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        deliveryState: ChatDeliveryState,
        clientMessageID: UUID = UUID(),
        source: String
    ) {
        let local = ChatMessage(
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            clientMessageID: clientMessageID,
            deliveryState: deliveryState
        )
        var messages = stateStore.persistedMessages(for: threadID)
        if messages.contains(where: { $0.clientMessageID == clientMessageID }) == false {
            messages.append(local)
            stateStore.setMessages(messages, for: threadID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.chatRepository.appendMessage(
                    threadID: threadID,
                    role: role,
                    kind: kind,
                    content: content,
                    attachments: [],
                    reasoningContent: nil,
                    reasoningDurationMs: nil,
                    reasoningExpanded: false,
                    reasoningVisibility: .full,
                    clientMessageID: clientMessageID,
                    serverMessageID: nil,
                    deliveryState: deliveryState
                )
                let latest = await self.loadChatMessagesUseCase.execute(threadID: threadID)
                await MainActor.run {
                    self.stateStore.setMessages(latest, for: threadID)
                }
                self.logger.info("本地对话状态消息已落库，source=\(source), thread=\(self.shortID(threadID))", module: .general)
            } catch {
                self.logger.error("本地对话状态消息落库失败，source=\(source), error=\(error.localizedDescription)", module: .general)
            }
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
        guard let index = attachments.firstIndex(where: { $0.type == .taskCards }),
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
        next[index] = attachments[index].withText(text)
        return next
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private static func managedFileRecord(for attachment: ChatAttachment) -> ManagedFileRecord {
        let resolvedPath = attachment.effectiveHTTPSImageDownloadURL?.absoluteString
            ?? attachment.url?.absoluteString
            ?? ""
        let parsed = attachment.sparkClientOSSFileUUIDAndFileName()
        let fileUUID = parsed?.fileUUID ?? attachment.id.uuidString
        let originalName =
            parsed?.fileName
            ?? attachment.url?.lastPathComponent.removingPercentEncoding
            ?? "attachment"
        let mimeType = FileUtilities.mimeType(forName: originalName)
        return ManagedFileRecord(
            id: attachment.fileId ?? 0,
            fileUUID: fileUUID,
            filePath: resolvedPath,
            originalName: originalName,
            fileSize: 0,
            mimeType: mimeType,
            fileMd5: attachment.fileMd5,
            isPublic: false,
            businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
            businessID: "",
            createdAt: "",
            objectKey: nil,
            storageType: nil
        )
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
        guard let index = attachments.firstIndex(where: { $0.type == .structuredHealthCards }),
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
        next[index] = attachments[index].withText(text)
        return next
    }
}
