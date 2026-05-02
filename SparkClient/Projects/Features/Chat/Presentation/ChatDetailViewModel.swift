import Combine
import Foundation
import SwiftUI

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
    private let updateChatMessageBlocksUseCase: UpdateChatMessageBlocksUseCase
    let toolInteractionCoordinator: ToolInteractionCoordinator
    private let notificationClient: any NotificationClient
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    private let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    private let taskManager: TaskManager
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
    @Published private(set) var chatScenarioModels: [AIScenarioRemoteModelRow] = []
    /// 对话场景可消费的小任务（本地 + 服务端，以 code 为唯一标识）。
    @Published private(set) var chatSmallTasks: [SmallTask] = []
    /// 当前会话输入栏关联模型的推理能力（用于思考开关展示策略）。
    @Published private(set) var reasoningToolbarContext: ChatModelReasoningContext = .unknown
    /// 当前会话在列表中的图片送达方式（用于工具栏菜单展示）。
    @Published private(set) var threadImageDeliveryMode: ChatThreadImageDeliveryMode = .directMultimodal
    /// 当前所选对话模型是否支持多模态（用于置灰「直发」选项）。
    @Published private(set) var currentModelSupportsMultimodal: Bool = false

    /// 工具详情 Sheet 渲染上下文（由消息气泡注入，关闭 Sheet 时清空）。
    @Published private(set) var toolPreviewRenderContext: ChatRenderContext?

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
        updateChatMessageBlocksUseCase: UpdateChatMessageBlocksUseCase,
        toolInteractionCoordinator: ToolInteractionCoordinator,
        notificationClient: any NotificationClient,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase,
        taskManager: TaskManager = .shared,
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
        self.updateChatMessageBlocksUseCase = updateChatMessageBlocksUseCase
        self.toolInteractionCoordinator = toolInteractionCoordinator
        self.notificationClient = notificationClient
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.translateKnowledgeTextUseCase = translateKnowledgeTextUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.saveTypedMedicalDocumentUseCase = saveTypedMedicalDocumentUseCase
        self.taskManager = taskManager
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
                let delay: UInt64 = streaming ? 1000 : 120
                self.chatLoadCoordinator.schedule(delayMs: delay) { [weak self] in
                    guard let self else { return }
                    await self.loadMessagesIfNeeded(for: threadID, skipRemoteSync: true)
                }
            }
            .store(in: &cancellables)
        toolInteractionCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// 打开工具输出详情全局 Sheet（与 consent/question 共用同一呈现队列）。
    func presentToolDetailPreview(prompt: ToolPreviewPrompt, renderContext: ChatRenderContext) {
        toolPreviewRenderContext = renderContext
        toolInteractionCoordinator.presentToolPreview(prompt: prompt)
    }

    func presentSystemMessageSettings(prompt: SystemMessageSettingsPrompt) {
        toolInteractionCoordinator.presentSystemMessageSettings(prompt: prompt)
    }

    func clearToolPreviewRenderContext() {
        toolPreviewRenderContext = nil
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
            chatSmallTasks = []
            return nil
        }
        
        // 提取聊天场景可用模型列表
        chatScenarioModels = bundles.chat.models
        chatSmallTasks = await aiConfigCenter.effectiveSmallTasks()

        // 校验并修正当前选中的模型（确保在可选列表内）
        await validateCurrentSelection(for: threadID)

        // 提取当前可选模型名称集合，为空则直接返回 nil
        let namesInPicker = Set(chatScenarioModels.map(\.name))
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
        return chatScenarioModels.first?.name
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
        let namesInPicker = Set(chatScenarioModels.map(\.name))
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
            try await syncChatUseCase.pushSingleThread(threadID: threadID)
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
            try await syncChatUseCase.pushSingleThread(threadID: threadID)
        } catch {
            logger.warning("线程参数上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    func updateThreadSystemPrompt(_ rolePrompt: String, for threadID: UUID) async {
        guard let thread = await chatRepository.loadThread(id: threadID) else { return }
        let trimmed = rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard thread.rolePrompt != trimmed else { return }

        await chatRepository.updateThreadGenerationConfig(
            threadID: threadID,
            currentModelName: thread.currentModelName,
            temperature: thread.temperature,
            topP: thread.topP,
            maxTokens: thread.maxTokens,
            maxMessages: thread.maxMessages,
            rolePrompt: trimmed
        )

        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            stateStore.upsertThreadListItem(item)
        }

        do {
            try await syncChatUseCase.pushSingleThread(threadID: threadID)
        } catch {
            logger.warning("会话系统消息上送失败，稍后重试：\(error.localizedDescription)", module: .general)
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
                    self.notificationClient.error(
                        error.localizedDescription,
                        title: L10n.text("common.error"),
                        source: "chat.sync.open"
                    )
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

    func startSmallTask(_ task: SmallTask) {
        guard currentGenerationTask == nil else { return }
        currentGenerationTask = Task { [weak self] in
            await self?.sendCurrentDraft(smallTask: task)
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

    /// 发送当前编辑框的草稿消息（主入口函数）
    func sendCurrentDraft(smallTask: SmallTask? = nil) async {
        // 防止重复发送：如果正在发送中，直接返回
        guard stateStore.isSending == false else { return }
        // 必须选中对话线程，否则无法发送
        guard let threadID = stateStore.selectedThreadID else { return }

        // 获取当前编辑框的草稿内容
        let composer = stateStore.composerDraft(for: threadID)
        // 必须有内容 或 有任务，才允许发送
        guard composer.hasVisualContent || smallTask != nil else { return }
        // 附件还在准备中，阻塞发送
        guard stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false else { return }

        // 清理文本首尾空白换行
        let draft = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 获取发送时的功能开关（工具、联网、知识库、推理等）
        let flags = composer.runtimeFlags
        // 构造AI推理选项
        let inference = ChatOrchestratorInferenceOptions(
            useTools: flags.useTools,
            useKnowledgeBag: flags.useKnowledgeBag,
            useWebSearch: flags.useWebSearch,
            reasoningEnabled: flags.reasoningEnabled,
            reasoningEffortTier: flags.reasoningEffortTier
        )

        // 日志：开始发送对话
        logger.info(
            "发送对话开始，thread=\(shortID(threadID)), member=\(shortID(memberContextStore.context.selectedMemberID)), textLen=\(draft.count), attachments=\(composer.attachments.count)",
            module: .general
        )
        
        // MARK: - 核心：创建取消令牌，用于中断本次AI生成
        let cancellationToken = AIRuntimeCancellationToken()
        currentGenerationCancellationToken = cancellationToken
        // 生成流式消息唯一ID
        let streamingMessageID = UUID()
        // 清理中断相关标记
        cancellationNoticeThreadIDs.remove(threadID)
        finalizedInterruptedAssistantMessageIDs.remove(streamingMessageID)
        
        // MARK: - 状态标记：正在发送
        stateStore.setSending(true)
        
        // MARK: - 无论成功失败，最后都要重置发送状态（ defer 最终一定会执行）
        defer {
            stateStore.setSending(false)
            if currentGenerationCancellationToken === cancellationToken {
                currentGenerationCancellationToken = nil
            }
            currentGenerationTask = nil
        }

        do {
            // 清除运行时配置覆盖
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            // 获取当前模型推理配置
            let modelReasoning = (try? await aiConfigCenter.effectiveScenarioBundles())?
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName) ?? .unknown
            
            // 清空附件上传进度
            let stateStore = self.stateStore
            stateStore.clearComposerAttachmentUploadProgress()
            
            // MARK: - 开始流式输出助手消息（界面显示加载/打字效果）
            stateStore.startStreamingAssistant(
                threadID: threadID,
                clientMessageID: streamingMessageID,
                kind: .text
            )
            
            let loadChatThreadsUseCase = self.loadChatThreadsUseCase
            
            // MARK: - 核心执行：发送消息到后端，处理流式返回
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
                smallTask: smallTask,
                cancellationToken: cancellationToken,
                
                // 图片上传进度回调 → 更新UI
                onImageUploadProgress: { id, progress in
                    Task { @MainActor in
                        stateStore.setComposerAttachmentUploadProgress(id: id, progress: progress)
                    }
                },
                
                // 用户消息已持久化回调 → 更新界面消息列表
                onUserMessagePersisted: { localSnapshot in
                    let listItem = await loadChatThreadsUseCase.execute(threadID: localSnapshot.thread.id)
                    await MainActor.run {
                        stateStore.setSelectedThreadID(localSnapshot.thread.id)
                        // 不清空流式占位，保证打字效果不中断
                        stateStore.setMessages(localSnapshot.messages, for: localSnapshot.thread.id, clearStreamingAssistant: false)
                        if let listItem {
                            stateStore.upsertThreadListItem(listItem)
                        }
                        // 清空发送成功的草稿
                        stateStore.clearDraft(for: localSnapshot.thread.id)
                    }
                },
                
                // 助手流式返回片段 → 实时追加到界面
                onAssistantPartial: { delta in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(threadID: threadID, delta: delta)
                    }
                }
            )

            // MARK: - 发送完成：刷新线程列表
            if let finalRow = await loadChatThreadsUseCase.execute(threadID: snapshot.thread.id) {
                stateStore.upsertThreadListItem(finalRow)
            }
            
            // 保存流式产生的附件
            await persistStreamingAttachmentsIfNeeded(
                threadID: snapshot.thread.id,
                assistantClientMessageID: streamingMessageID
            )
            
            // 加载最终完整消息
            let finalMessages = await loadChatMessagesUseCase.execute(threadID: snapshot.thread.id)
            stateStore.setMessages(finalMessages, for: snapshot.thread.id)
            // 清空草稿、清除错误
            stateStore.clearDraft(for: snapshot.thread.id)
            stateStore.setError(nil, for: snapshot.thread.id)
            
            // 日志：发送成功
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
            
        }
        // MARK: - 用户主动取消发送
        catch is CancellationError {
            persistInterruptedAssistantIfNeeded(threadID: threadID, source: "chat.cancel.catch")
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            appendCancellationNoticeIfNeeded(threadID: threadID)
            logger.info("发送对话已中断，thread=\(shortID(threadID))", module: .general)
        }
        // MARK: - 发送失败（网络/服务异常）
        catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(nil, for: threadID)
            // 显示错误卡片
            if shouldRenderAssistantErrorCard(for: error) {
                appendAssistantErrorMessage(
                    threadID: threadID,
                    assistantClientMessageID: streamingMessageID,
                    error: error
                )
            }
            logger.error("发送对话失败：\(error.localizedDescription)", module: .general)
            // 弹出系统错误提示
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
        await clearAssistantErrorMessageIfNeeded(
            threadID: threadID,
            messages: messages,
            preferredClientMessageID: preferredClientMessageID
        )
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
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.sync")
        }
    }

    /// 清空指定会话的所有历史消息，保留会话本身与参数配置。
    func clearMessages(for threadID: UUID) async {
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID, limit: nil, before: nil)
        guard messages.isEmpty == false else {
            await MainActor.run {
                stateStore.setMessages([], for: threadID, hasMore: false)
                stateStore.clearDraft(for: threadID)
                stateStore.setError(nil, for: threadID)
            }
            return
        }

        for message in messages {
            await chatRepository.softDeleteMessage(clientMessageID: message.clientMessageID)
        }

        let refreshedMessages = await loadChatMessagesUseCase.execute(threadID: threadID, limit: nil, before: nil)
        await MainActor.run {
            stateStore.setMessages(refreshedMessages, for: threadID, hasMore: false)
            stateStore.clearDraft(for: threadID)
            stateStore.setError(nil, for: threadID)
        }
        if let listItem = await loadChatThreadsUseCase.execute(threadID: threadID) {
            await MainActor.run {
                stateStore.upsertThreadListItem(listItem)
            }
        }

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("清空聊天记录后上送失败，稍后重试：\(error.localizedDescription)", module: .general)
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
            await persistStreamingAttachmentsIfNeeded(
                threadID: snapshot.thread.id,
                assistantClientMessageID: streamingMessageID
            )
            let finalMessages = await loadChatMessagesUseCase.execute(threadID: snapshot.thread.id)
            stateStore.setMessages(finalMessages, for: snapshot.thread.id)
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
            if shouldRenderAssistantErrorCard(for: error) {
                appendAssistantErrorMessage(
                    threadID: threadID,
                    assistantClientMessageID: streamingMessageID,
                    error: error
                )
            }
            logger.error("重新生成回答失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    private func clearAssistantErrorMessageIfNeeded(
        threadID: UUID,
        messages: [ChatMessage],
        preferredClientMessageID: UUID?
    ) async {
        let targetMessage: ChatMessage?
        if let preferredClientMessageID,
           preferredClientMessageID != ChatView.inlineErrorClientMessageID {
            targetMessage = messages.first(where: { $0.clientMessageID == preferredClientMessageID })
        } else {
            targetMessage = messages.last(where: { message in
                message.role == .assistant
                    && message.deliveryState == .failed
                    && message.blocks.contains(where: { $0.kind == .error })
            })
        }
        guard let targetMessage,
              targetMessage.role == .assistant,
              targetMessage.deliveryState == .failed else {
            return
        }

        await chatRepository.softDeleteMessage(clientMessageID: targetMessage.clientMessageID)
        let refreshed = await loadChatMessagesUseCase.execute(threadID: threadID)
        await MainActor.run {
            self.stateStore.setMessages(refreshed, for: threadID)
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

    private func persistStreamingAttachmentsIfNeeded(
        threadID: UUID,
        assistantClientMessageID: UUID
    ) async {
        guard let streaming = stateStore.activeStreamingAssistantMessage(for: threadID),
              streaming.blocks.isEmpty == false else { return }
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
        guard let target = messages.last(where: { $0.clientMessageID == assistantClientMessageID }) else { return }
        let mergedBlocks = ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: target.blocks,
            incomingBlocks: streaming.blocks
        )
        guard mergedBlocks != target.blocks else { return }
        await updateChatMessageBlocksUseCase.execute(
            clientMessageID: assistantClientMessageID,
            blocks: mergedBlocks,
            markPendingForSync: true
        )
        stateStore.updateMessageBlocksSnapshot(
            threadID: threadID,
            clientMessageID: assistantClientMessageID,
            blocks: mergedBlocks
        )
    }

    @discardableResult
    private func persistInterruptedAssistantIfNeeded(threadID: UUID, source: String) -> Bool {
        guard let streaming = stateStore.activeStreamingAssistantMessage(for: threadID) else {
            logger.debug("中断固化跳过：无流式助手消息，source=\(source), thread=\(shortID(threadID))", module: .general)
            return false
        }

        let content = streaming.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDeepThought = streaming.blocks.contains(where: { $0.kind == .deepThought })
        let hasAttachmentBlocks = streaming.blocks.contains { $0.kind == .imageGallery || $0.kind == .fileAttachments }
        guard content.isEmpty == false || hasDeepThought || hasAttachmentBlocks else {
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
            blocks: streaming.blocks,
            clientMessageID: streaming.clientMessageID,
            serverMessageID: nil,
            deliveryState: .pending,
            createdAt: streaming.createdAt,
            serverUpdatedAt: nil,
            isTombstone: false,
            modelName: streaming.modelName
        )

        var messages = stateStore.persistedMessages(for: threadID)
        if messages.contains(where: { $0.clientMessageID == finalized.clientMessageID }) == false {
            messages.append(finalized)
            stateStore.setMessages(messages, for: threadID, clearStreamingAssistant: false)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.chatRepository.appendMessage(finalized)
                await self.sendMessageUseCase.pushPendingMessages(source: source)
                let latest = await self.loadChatMessagesUseCase.execute(threadID: threadID)
                await MainActor.run {
                    self.stateStore.setMessages(latest, for: threadID)
                }
                let finalizedTextLength = finalized.blocks
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .count
                self.logger.info(
                    "中断时已固化 AI 已生成内容，source=\(source), thread=\(self.shortID(threadID)), clientMessageID=\(self.shortID(finalized.clientMessageID)), contentLength=\(finalizedTextLength)",
                    module: .general
                )
            } catch {
                self.logger.error(
                    "中断时固化 AI 已生成内容失败，source=\(source), thread=\(self.shortID(threadID)), error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }

        let finalizedTextLength = finalized.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .count
        logger.info(
            "中断时保留 AI 已生成内容到本地列表，source=\(source), thread=\(shortID(threadID)), clientMessageID=\(shortID(finalized.clientMessageID)), contentLength=\(finalizedTextLength)",
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
            blocks: [ChatMessageBlock(kind: .text, text: content)],
            clientMessageID: clientMessageID,
            deliveryState: deliveryState,
            modelName: role.rawValue
        )
        var messages = stateStore.persistedMessages(for: threadID)
        if messages.contains(where: { $0.clientMessageID == clientMessageID }) == false {
            messages.append(local)
            stateStore.setMessages(messages, for: threadID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.chatRepository.appendMessage(local)
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

    private func shouldRenderAssistantErrorCard(for error: Error) -> Bool {
        unwrapAIRuntimeError(from: error).map {
            if case .server = $0 {
                return true
            }
            return false
        } ?? false
    }

    private func unwrapAIRuntimeError(from error: Error) -> AIRuntimeError? {
        if let runtimeError = error as? AIRuntimeError {
            return runtimeError
        }

        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return unwrapAIRuntimeError(from: underlying)
        }

        return nil
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
        // 直接将整条消息保存为知识文档。
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

    func handleTaskCardAction(
        threadID: UUID,
        message: ChatMessage,
        action: TaskCard.Action
    ) async {
        switch action {
        case .confirm(let card):
            await confirmTaskCard(threadID: threadID, message: message, card: card)
        case .ignore(let card):
            await updateTaskCard(threadID: threadID, message: message, cardID: card.id) {
                $0.status = .ignored
                $0.updatedAt = Date()
            }
            logger.info("任务卡片本地忽略 card_id=\(card.id)", module: .general)
        case .setMember(let card, let memberID):
            await updateTaskCard(threadID: threadID, message: message, cardID: card.id) {
                $0.member = memberID
                $0.taskPayload = Self.taskPayload($0.taskPayload, settingMemberID: memberID)
                $0.updatedAt = Date()
            }
        }
    }

    private func confirmTaskCard(threadID: UUID, message: ChatMessage, card: TaskCard) async {
        guard let memberID = validatedTaskCardMemberID(card.member) else { return }
        var cardToCreate = card
        cardToCreate.member = memberID
        cardToCreate.taskPayload = Self.taskPayload(card.taskPayload, settingMemberID: memberID)

        do {
            let payload = ChatTaskPayloadBuilder.build(from: cardToCreate)
            try await taskManager.createTask(payload: payload)
            logger.info("任务卡片直接创建任务成功 card_id=\(card.id)", module: .general)
            await updateTaskCard(threadID: threadID, message: message, cardID: card.id) {
                $0.member = memberID
                $0.taskPayload = cardToCreate.taskPayload
                $0.status = .confirmed
                $0.updatedAt = Date()
            }
        } catch {
            logger.error("任务卡片直接创建任务失败 card_id=\(card.id) error=\(error.localizedDescription)", module: .general)
        }
    }

    private func validatedTaskCardMemberID(_ memberID: Int?) -> Int? {
        guard let memberID, memberID > 0 else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.task_card.create")
            return nil
        }
        return memberID
    }

    private static func taskPayload(_ payload: [String: String], settingMemberID memberID: Int?) -> [String: String] {
        var next = payload
        var taskJSON = jsonObject(from: payload["task"])
        if let memberID {
            taskJSON["member_id"] = memberID
            taskJSON["member"] = memberID
        } else {
            taskJSON.removeValue(forKey: "member_id")
            taskJSON.removeValue(forKey: "member")
        }
        next["task"] = jsonString(from: taskJSON) ?? payload["task"] ?? "{}"
        return next
    }

    private static func jsonObject(from text: String?) -> [String: Any] {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func jsonString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func updateTaskCard(
        threadID: UUID,
        message: ChatMessage,
        cardID: Int,
        mutate: (inout TaskCard) -> Void
    ) async {
        guard let updatedBlocks = replacingTaskCard(in: message.blocks, cardID: cardID, mutate: mutate) else { return }
        await updateChatMessageBlocksUseCase.execute(
            clientMessageID: message.clientMessageID,
            blocks: updatedBlocks,
            markPendingForSync: true
        )

        stateStore.updateMessageBlocksFromIncoming(
            threadID: threadID,
            clientMessageID: message.clientMessageID,
            incomingBlocks: updatedBlocks
        )

        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("任务卡状态上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    private func replacingTaskCard(
        in blocks: [ChatMessageBlock],
        cardID: Int,
        mutate: (inout TaskCard) -> Void
    ) -> [ChatMessageBlock]? {
        guard let index = blocks.lastIndex(where: { $0.kind == .taskCards }) else {
            return nil
        }
        var cards = blocks[index].taskCards
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardID }) else { return nil }
        mutate(&cards[cardIndex])
        var next = blocks
        let old = blocks[index]
        next[index] = ChatMessageBlock(
            id: old.id,
            anchor: old.anchor,
            kind: .taskCards,
            toolCallID: old.toolCallID,
            taskCards: cards,
            createdAt: old.createdAt,
            updatedAt: Date()
        )
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

    // MARK: - 等待成员工具：成员选择写入

    func setPendingMemberToolSelection(
        threadID: UUID,
        message: ChatMessage,
        card: PendingMemberToolCard,
        memberID: Int?
    ) async {
        guard let memberID, memberID > 0 else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.pending_member_tool")
            return
        }

        await updateThreadMemberBinding(memberID, for: threadID)
        memberContextStore.select(memberID: memberID)

        updatePendingMemberToolCardInCache(threadID: threadID, message: message, cardID: card.id) {
            $0.selectedMemberID = memberID
            $0.status = .completed
            $0.arguments["member_id"] = String(memberID)
            $0.resultText = L10n.text("tool.result.request_member_selection.completed")
            $0.updatedAt = Date()
        }
    }

    private func updatePendingMemberToolCardInCache(
        threadID: UUID,
        message: ChatMessage,
        cardID: UUID,
        mutate: (inout PendingMemberToolCard) -> Void
    ) {
        guard let updated = replacingPendingMemberToolCard(in: message.blocks, cardID: cardID, mutate: mutate),
              let pending = updated.last(where: { $0.kind == .pendingMemberToolCards }) else { return }
        stateStore.mergeStreamingAssistantAttachments(
            threadID: threadID,
            incomingBlocks: [pending]
        )
    }

    private func updatePendingMemberToolCard(
        threadID: UUID,
        message: ChatMessage,
        cardID: UUID,
        mutate: (inout PendingMemberToolCard) -> Void
    ) async {
        guard let updated = replacingPendingMemberToolCard(in: message.blocks, cardID: cardID, mutate: mutate) else { return }
        await persistStructuredBlocks(threadID: threadID, message: message, blocks: updated)
    }

    private func replacingPendingMemberToolCard(
        in blocks: [ChatMessageBlock],
        cardID: UUID,
        mutate: (inout PendingMemberToolCard) -> Void
    ) -> [ChatMessageBlock]? {
        for (index, block) in blocks.enumerated() {
            guard block.kind == .pendingMemberToolCards else { continue }
            var cards = block.pendingMemberToolCards
            guard let cardIndex = cards.firstIndex(where: { $0.id == cardID }) else { continue }
            mutate(&cards[cardIndex])
            var next = blocks
            next[index] = ChatMessageBlock(
                id: block.id,
                anchor: block.anchor,
                kind: .pendingMemberToolCards,
                toolCallID: block.toolCallID,
                pendingMemberToolCards: cards,
                createdAt: block.createdAt,
                updatedAt: Date()
            )
            return next
        }
        return nil
    }

    // MARK: - 对话内结构化医疗卡片保存

    func handleStructuredHealthCardAction(
        threadID: UUID,
        message: ChatMessage,
        action: ChatStructuredHealthCardAction
    ) async {
        switch action {
        case .save(let item):
            await saveStructuredHealthCard(threadID: threadID, message: message, item: item)
        case .setMember(let item, let memberID):
            await updateStructuredHealthCardMember(threadID: threadID, message: message, item: item, memberID: memberID)
        }
    }

    private func saveStructuredHealthCard(threadID: UUID, message: ChatMessage, item: ChatStructuredHealthCardItem) async {
        guard let output = makeStructuredHealthCardSaveOutput(for: item) else { return }
        await saveWithCardId(item.id, rawTrace: item.rawTrace) {
            output
        } onSuccess: {
            await updateStructuredHealthCardsBlob(threadID: threadID, message: message) {
                $0.markSaved(item)
            }
        }
    }

    /// 统一的医疗卡片保存执行方法（封装通用保存逻辑）
    /// - Parameters:
    ///   - cardID: 卡片唯一ID
    ///   - rawTrace: 日志追踪标识
    ///   - buildOutput: 构建医疗文档输出结果的闭包
    ///   - onSuccess: 保存成功回调
    private func saveWithCardId(
        _ cardID: UUID,
        rawTrace: String,
        buildOutput: () throws -> MedicalDocumentTypedExtractionOutput,
        onSuccess: () async -> Void
    ) async {
        // 标记卡片正在保存中，防止重复保存
        savingStructuredHealthCardIDs.insert(cardID)
        // 方法结束时移除保存中标记（无论成功失败）
        defer { savingStructuredHealthCardIDs.remove(cardID) }
        
        do {
            // 构建保存所需的输出数据
            let output = try buildOutput()
            // 执行保存用例
            _ = try await saveTypedMedicalDocumentUseCase.execute(output: output)
            
            // 保存成功：提示用户 + 打印日志 + 执行成功回调
            notificationClient.success(
                L10n.text("chat.medical_card.saved.toast"),
                title: nil,
                source: "chat.medical.save"
            )
            logger.info("对话医疗卡片已保存 trace=\(rawTrace)", module: .general)
            await onSuccess()
        } catch {
            // 保存失败：打印错误日志 + 提示用户
            logger.error("对话医疗卡片保存失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.medical.save")
        }
    }

    private func makeStructuredHealthCardSaveOutput(for item: ChatStructuredHealthCardItem) -> MedicalDocumentTypedExtractionOutput? {
        guard let memberID = validatedCardMemberID(item.memberID) else {
            return nil
        }
        guard let data = item.draftJSON.data(using: .utf8) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return nil
        }

        switch item {
        case .medication:
            guard let draft = decodeStructuredHealthCardDraft(MedicationRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .medication,
                rawText: item.rawTrace,
                typedResult: .medication([draft]),
                extractedJSON: item.draftJSON
            )
        case .prescription:
            guard let draft = decodeStructuredHealthCardDraft(PrescriptionRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .prescription,
                rawText: item.rawTrace,
                typedResult: .prescription(draft),
                extractedJSON: item.draftJSON
            )
        case .examReport:
            if let report = try? JSONDecoder().decode(MedicalReportRecognitionDraft.self, from: data) {
                return makeStructuredHealthCardSaveOutput(
                    memberID: memberID,
                    kind: .medicalReport,
                    rawText: item.rawTrace,
                    typedResult: .medicalReport([report]),
                    extractedJSON: item.draftJSON
                )
            }
            if let health = try? JSONDecoder().decode(HealthExamRecognitionDraft.self, from: data) {
                return makeStructuredHealthCardSaveOutput(
                    memberID: memberID,
                    kind: .healthExamReport,
                    rawText: item.rawTrace,
                    typedResult: .healthExamReport(health),
                    extractedJSON: item.draftJSON
                )
            }
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return nil
        case .medicalCase:
            guard let draft = decodeStructuredHealthCardDraft(CaseRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .caseDocument,
                rawText: item.rawTrace,
                typedResult: .caseDocument(draft),
                extractedJSON: item.draftJSON
            )
        }
    }

    private func decodeStructuredHealthCardDraft<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard let draft = try? JSONDecoder().decode(type, from: data) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return nil
        }
        return draft
    }

    private func makeStructuredHealthCardSaveOutput(
        memberID: Int,
        kind: MedicalDocumentKind,
        rawText: String,
        typedResult: MedicalDocumentTypedResult,
        extractedJSON: String
    ) -> MedicalDocumentTypedExtractionOutput {
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: [],
            rawOCRText: rawText,
            typeResolution: MedicalDocumentTypeResolution(
                kind: kind,
                confidence: 1,
                source: .manual,
                reason: "chat_save"
            )
        )
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: typedResult,
            extractedJSON: extractedJSON,
            payloadPreview: ""
        )
    }

    private func validatedCardMemberID(_ memberID: Int?) -> Int? {
        guard let memberID, memberID > 0 else {
            notificationClient.error(L10n.text("chat.medical_card.error.no_member"), title: nil, source: "chat.medical.save")
            return nil
        }
        return memberID
    }

    private func updateStructuredHealthCardMember(
        threadID: UUID,
        message: ChatMessage,
        item: ChatStructuredHealthCardItem,
        memberID: Int?
    ) async {
        await updateStructuredHealthCardsBlob(threadID: threadID, message: message) {
            $0.updateMember(item, memberID: memberID)
        }
    }

    // MARK: - 卡片状态标记（更新消息 blocks 中卡片状态）

    private func updateStructuredHealthCardsBlob(
        threadID: UUID,
        message: ChatMessage,
        mutate: (inout StructuredHealthCardsBlob) -> Void
    ) async {
        guard let updated = replacingStructuredHealthCardsBlob(in: message.blocks, mutate: mutate) else { return }
        await persistStructuredBlocks(threadID: threadID, message: message, blocks: updated)
    }

    // MARK: - Blocks 持久化与同步

    /// 持久化更新后的结构化卡片 blocks，并同步到服务端
    private func persistStructuredBlocks(threadID: UUID, message: ChatMessage, blocks: [ChatMessageBlock]) async {
        await updateChatMessageBlocksUseCase.execute(
            clientMessageID: message.clientMessageID,
            blocks: blocks,
            markPendingForSync: true
        )
        
        // 更新本地状态存储
        stateStore.updateMessageBlocksFromIncoming(
            threadID: threadID,
            clientMessageID: message.clientMessageID,
            incomingBlocks: blocks
        )
        
        // 执行同步：推送本地数据到服务端
        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("医疗卡片状态上送失败，稍后重试：\(error.localizedDescription)", module: .general)
        }
    }

    /// 替换消息 blocks 中的结构化健康卡片数据
    /// - Parameters:
    ///   - blocks: 原始消息 blocks
    ///   - mutate: 修改卡片数据的闭包
    /// - Returns: 修改后的消息 blocks
    private func replacingStructuredHealthCardsBlob(
        in blocks: [ChatMessageBlock],
        mutate: (inout StructuredHealthCardsBlob) -> Void
    ) -> [ChatMessageBlock]? {
        guard let index = blocks.lastIndex(where: { $0.kind == .structuredHealthCards }),
              var blob = blocks[index].structuredHealthCards else {
            return nil
        }
        
        // 执行修改操作
        mutate(&blob)
        
        var next = blocks
        let old = blocks[index]
        next[index] = ChatMessageBlock(
            id: old.id,
            anchor: old.anchor,
            kind: .structuredHealthCards,
            toolCallID: old.toolCallID,
            structuredHealthCards: blob,
            createdAt: old.createdAt,
            updatedAt: Date()
        )
        return next
    }
}
