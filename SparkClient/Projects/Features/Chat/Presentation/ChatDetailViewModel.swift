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
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let fileTransferService: FileTransferService
    private let ocrOrchestrator: OCROrchestrator
    private let ocrDocumentExtractor: OCRDocumentExtractor
    private let retryFailedMessageUseCase: RetryFailedMessageUseCase
    private let updateChatMessageBlocksUseCase: UpdateChatMessageBlocksUseCase
    private let chatSyncSupervisor: ChatSyncSupervisor
    let toolInteractionCoordinator: ToolInteractionCoordinator
    private let notificationClient: any NotificationClient
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    private let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    private let taskManager: TaskManager
    private let logger: Logger
    private var composerAttachmentTasks: [UUID: Task<Void, Never>] = [:]
    private var currentGenerationTask: Task<Void, Never>?
    private var currentGenerationCancellationToken: AIRuntimeCancellationToken?
    private var currentGenerationAssistantClientMessageID: UUID?
    private var finalizedInterruptedAssistantMessageIDs: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private let chatLoadCoordinator = ChatLoadCoordinator()

    /// 结构化医疗卡片保存中（用于按钮 Progress）。
    @Published private(set) var savingStructuredHealthCardIDs: Set<UUID> = []
    /// 营养卡片写入 Apple 健康中（用于按钮 Progress）。
    @Published private(set) var savingNutritionCardIDs: Set<UUID> = []

    /// 对话场景可选模型行（远程场景 + 本地/智能体模型），供 Hanlin 输入栏展示。
    @Published private(set) var chatScenarioModels: [AIScenarioRemoteModelRow] = []
    /// 对话场景可消费的小任务（本地 + 服务端，以 code 为唯一标识）。
    @Published private(set) var chatSmallTasks: [SmallTask] = []
    /// 系统提示词编辑器可直接消费的提示词库模板。
    @Published private(set) var chatPromptTemplates: [PromptRepo] = []
    /// 当前会话输入栏关联模型的推理能力（用于思考开关展示策略）。
    @Published private(set) var reasoningToolbarContext: ChatModelReasoningContext = .unknown
    /// 当前会话在列表中的图片送达方式（用于工具栏菜单展示）。
    @Published private(set) var threadImageDeliveryMode: ChatThreadImageDeliveryMode = .directMultimodal
    /// 当前所选对话模型是否支持多模态（用于置灰「直发」选项）。
    @Published private(set) var currentModelSupportsMultimodal: Bool = false

    /// 工具详情 Sheet 渲染上下文（由消息气泡注入，关闭 Sheet 时清空）。
    @Published private(set) var toolPreviewRenderContext: ChatRenderContext?

    /// 首页已缓存的成员 complete-data，供消息流健康资料卡片本地命中（不触发全量拉取）。
    private(set) var cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?

    init(
        stateStore: ChatStateStore,
        memberContextStore: MemberContextStore,
        chatRepository: any ChatRepository,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        medicalQueryAPI: SparkMedicalQueryAPI,
        fileTransferService: FileTransferService,
        ocrOrchestrator: OCROrchestrator,
        ocrDocumentExtractor: OCRDocumentExtractor,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        updateChatMessageBlocksUseCase: UpdateChatMessageBlocksUseCase,
        chatSyncSupervisor: ChatSyncSupervisor,
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
        self.medicalQueryAPI = medicalQueryAPI
        self.fileTransferService = fileTransferService
        self.ocrOrchestrator = ocrOrchestrator
        self.ocrDocumentExtractor = ocrDocumentExtractor
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.updateChatMessageBlocksUseCase = updateChatMessageBlocksUseCase
        self.chatSyncSupervisor = chatSyncSupervisor
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
                    case .messagesUpdated:
                        let currentIDs = Set(self.stateStore.persistedMessages(for: threadID).map(\.clientMessageID))
                        let affected = event.affectedClientMessageIDs.filter(currentIDs.contains)
                        guard affected.isEmpty == false else { return }
                        self.chatLoadCoordinator.schedule(delayMs: 60) { [weak self] in
                            guard let self else { return }
                            let messages = await self.loadChatMessagesUseCase.execute(clientMessageIDs: affected)
                            await MainActor.run {
                                self.stateStore.updateMessages(messages, for: threadID)
                            }
                        }
                        return
                    case .messagesMerged:
                        self.chatLoadCoordinator.schedule(delayMs: 60) { [weak self] in
                            guard let self else { return }
                            await self.loadMessagesIfNeeded(
                                for: threadID,
                                lockBottomViewport: true,
                                syncRemote: false
                            )
                        }
                        return
                    }
                }
                self.chatLoadCoordinator.schedule(delayMs: 60) { [weak self] in
                    guard let self else { return }
                    await self.loadMessagesIfNeeded(for: threadID, syncRemote: false)
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

    func presentAskReportPicker(for threadID: UUID, memberID: Int?) {
        guard let memberID, memberID > 0 else { return }
        let prompt = AskReportPickerPrompt(threadID: threadID, memberID: memberID)
        toolInteractionCoordinator.presentAskReportPicker(prompt: prompt)
    }

    func appendAskReportRefs(_ refs: [HealthResourceRef], for threadID: UUID) {
        guard refs.isEmpty == false else { return }
        let draft = stateStore.composerDraft(for: threadID)
        let remaining = HealthResourceSendValidator.maxRefs - draft.pendingHealthResourceRefs.count
        guard remaining > 0 else {
            notifyAskReportMaxRefsReached()
            return
        }
        let batch = Array(refs.prefix(remaining))
        if batch.isEmpty {
            notifyAskReportMaxRefsReached()
            return
        }
        stateStore.appendHealthResourceRefs(batch, for: threadID)
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

    /// 聊天附件 UI 下载（画廊/列表/文件块，与 ``MedicalAttachmentGridPreview`` 共用 ``FileTransferService``）。
    var attachmentFileTransferService: FileTransferService { fileTransferService }

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
                        businessId: attachment.id.uuidString,
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
            chatPromptTemplates = []
            return nil
        }
        
        // 提取聊天场景可用模型列表
        chatScenarioModels = bundles.chat.models
        chatSmallTasks = await aiConfigCenter.effectiveSmallTasks()
        let snapshot = await aiConfigCenter.currentSnapshot()
        chatPromptTemplates = snapshot.promptRepo

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

    /// 新建会话前校验：当前运行时是否存在可用于聊天场景的模型。
    func hasAvailableChatModel() async -> Bool {
        guard let bundles = try? await aiConfigCenter.effectiveScenarioBundles() else {
            chatScenarioModels = []
            logger.warning(
                "聊天详情：无可用对话模型（effectiveScenarioBundles 失败，常见原因：未 prewarm 或 SessionSnapshot 无 accountID）",
                module: .general
            )
            return false
        }
        chatScenarioModels = bundles.chat.models
        if chatScenarioModels.isEmpty {
            logger.warning(
                "聊天详情：chat 场景模型列表为空，无法新建/发送对话",
                module: .general
            )
            return false
        }
        return true
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
        stateStore.pruneHealthResourceRefs(matchingMemberID: memberID, for: threadID)
    }

    var sparkMedicalQueryAPI: SparkMedicalQueryAPI { medicalQueryAPI }
    var chatNotificationClient: any NotificationClient { notificationClient }
    var chatLogger: Logger { logger }

    func updateCachedMemberCompleteData(_ data: SparkMedicalSyncAPI.RemoteMemberCompleteData?) {
        cachedMemberCompleteData = data
    }

    func fetchMemberCompleteData(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData {
        try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
    }

    func notifyHealthResourceUnavailable() {
        notificationClient.info(
            L10n.text("chat.ask_report.message_card.unavailable"),
            title: nil,
            source: "chat.health_resource.unavailable"
        )
    }

    func notifyAskReportMaxRefsReached() {
        notificationClient.info(
            L10n.text("chat.ask_report.toast.max_refs"),
            title: nil,
            source: "chat.ask_report.max_refs"
        )
    }

    func notifyAskReportDuplicateInPreview() {
        notificationClient.info(
            L10n.text("chat.ask_report.toast.duplicate_in_preview"),
            title: nil,
            source: "chat.ask_report.duplicate_in_preview"
        )
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

    }

    func loadMessagesIfNeeded(
        for threadID: UUID,
        lockBottomViewport: Bool = false,
        syncRemote: Bool = true
    ) async {
        await satisfyLoadRequest(
            .openOrReloadNewest(
                threadID: threadID,
                lockBottomViewport: lockBottomViewport
            )
        )
        guard syncRemote else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.chatSyncSupervisor.pullThreadMessagesIncrementalOnOpen(threadID: threadID)
            } catch {
                self.logger.debug(
                    "进入会话拉取增量失败，thread=\(self.shortID(threadID)), error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }
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
        case .openOrReloadNewest(let threadID, let lockBottomViewport):
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
                hasMore: hasMore
            )
            stateStore.requestScrollToBottom(for: threadID)
            if lockBottomViewport {
                stateStore.endBottomViewportLock(for: threadID)
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

    func startSendingCurrentDraft(sendsOriginalImagesToAI: Bool = false) {
        guard currentGenerationTask == nil else { return }
        currentGenerationTask = Task { [weak self] in
            await self?.sendCurrentDraft(sendsOriginalImagesToAI: sendsOriginalImagesToAI)
        }
    }

    func startSmallTask(_ task: SmallTask, sendsOriginalImagesToAI: Bool = false) {
        guard currentGenerationTask == nil else { return }
        currentGenerationTask = Task { [weak self] in
            await self?.sendCurrentDraft(
                smallTask: task,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI
            )
        }
    }

    func cancelCurrentGeneration() {
        guard let threadID = stateStore.selectedThreadID else { return }
        guard stateStore.isSending || currentGenerationCancellationToken != nil || currentGenerationTask != nil else { return }

        logger.info("用户中断 AI 生成，thread=\(shortID(threadID))", module: .general)
        let assistantClientMessageID = currentGenerationAssistantClientMessageID
        currentGenerationCancellationToken?.cancel()
        currentGenerationTask?.cancel()
        stateStore.setSending(false)
        stateStore.setError(nil, for: threadID)
        Task { [weak self] in
            guard let self, let assistantClientMessageID else { return }
            await self.finalizeInterruptedAssistantMessageIfNeeded(
                threadID: threadID,
                assistantClientMessageID: assistantClientMessageID
            )
        }
    }

    /// 发送当前编辑框的草稿消息（主入口函数）
    func sendCurrentDraft(
        smallTask: SmallTask? = nil,
        sendsOriginalImagesToAI: Bool = false
    ) async {
        // 防止重复发送：如果正在发送中，直接返回
        guard stateStore.isSending == false else { return }
        // 必须选中对话线程，否则无法发送
        guard let threadID = stateStore.selectedThreadID else { return }

        // 获取当前编辑框的草稿内容
        let composer = stateStore.composerDraft(for: threadID)
        let pendingHealthRefs = composer.pendingHealthResourceRefs
        // 必须有内容 或 有任务，才允许发送
        guard composer.hasVisualContent || smallTask != nil else { return }
        // 附件还在准备中，阻塞发送
        guard stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false else { return }

        do {
            try HealthResourceSendValidator.validate(
                refs: pendingHealthRefs,
                threadMemberID: stateStore.selectedThread?.memberID
            )
        } catch {
            notificationClient.info(error.localizedDescription, title: nil, source: "chat.ask_report.send")
            return
        }

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
            "发送对话开始，thread=\(shortID(threadID)), member=\(shortID(memberContextStore.context.selectedMemberID)), textLen=\(draft.count), attachments=\(composer.attachments.count), healthRefs=\(pendingHealthRefs.count)",
            module: .general
        )
        
        // MARK: - 核心：创建取消令牌，用于中断本次AI生成
        let cancellationToken = AIRuntimeCancellationToken()
        currentGenerationCancellationToken = cancellationToken
        // 生成流式消息唯一ID
        let streamingMessageID = UUID()
        currentGenerationAssistantClientMessageID = streamingMessageID
        // 清理中断相关标记
        finalizedInterruptedAssistantMessageIDs.remove(streamingMessageID)
        
        // MARK: - 状态标记：正在发送
        stateStore.setSending(true)
        stateStore.requestScrollToBottom(for: threadID)
        
        // MARK: - 无论成功失败，最后都要重置发送状态（ defer 最终一定会执行）
        defer {
            stateStore.setSending(false)
            if currentGenerationCancellationToken === cancellationToken {
                currentGenerationCancellationToken = nil
            }
            if currentGenerationAssistantClientMessageID == streamingMessageID {
                currentGenerationAssistantClientMessageID = nil
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
            
            let loadChatThreadsUseCase = self.loadChatThreadsUseCase
            
            // MARK: - 核心执行：发送消息到后端，处理流式返回
            let snapshot = try await sendMessageUseCase.execute(
                threadID: threadID,
                memberID: memberContextStore.context.selectedMemberID,
                userInput: composer.text,
                composerAttachments: composer.attachments,
                preparedAttachments: stateStore.preparedAttachments(for: threadID),
                healthResourceRefs: pendingHealthRefs,
                selectedChatModelName: flags.selectedChatModelName,
                assistantClientMessageID: streamingMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                smallTask: smallTask,
                sendsOriginalImagesToAI: sendsOriginalImagesToAI,
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
                        stateStore.setMessages(localSnapshot.messages, for: localSnapshot.thread.id)
                        stateStore.requestScrollToBottom(for: localSnapshot.thread.id)
                        if let listItem {
                            stateStore.upsertThreadListItem(listItem)
                        }
                        // 清空发送成功的草稿
                        stateStore.clearDraft(for: localSnapshot.thread.id)
                    }
                },
                
                // Streaming deltas are persisted by SendChatMessageUseCase and rendered through DB notifications.
                onAssistantPartial: nil,
                cachedMemberCompleteData: cachedMemberCompleteData
            )

            // MARK: - 发送完成：刷新线程列表
            if let finalRow = await loadChatThreadsUseCase.execute(threadID: snapshot.thread.id) {
                stateStore.upsertThreadListItem(finalRow)
            }
            
            // 加载最终完整消息
            let finalMessages = await loadChatMessagesUseCase.execute(threadID: snapshot.thread.id)
            stateStore.setMessages(finalMessages, for: snapshot.thread.id)
            // 清空已发送的文本/附件
            stateStore.clearComposerTextAndAttachments(for: snapshot.thread.id)
            stateStore.setError(nil, for: snapshot.thread.id)
            
            // 日志：发送成功
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
            
        }
        // MARK: - 用户主动取消发送
        catch is CancellationError {
            stateStore.setError(nil, for: threadID)
            await finalizeInterruptedAssistantMessageIfNeeded(
                threadID: threadID,
                assistantClientMessageID: streamingMessageID
            )
            logger.info("发送对话已中断，thread=\(shortID(threadID))", module: .general)
        }
        // MARK: - 发送失败（网络/服务异常）
        catch {
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
        currentGenerationAssistantClientMessageID = streamingMessageID
        finalizedInterruptedAssistantMessageIDs.remove(streamingMessageID)
        stateStore.setSending(true)
        defer {
            stateStore.setSending(false)
            if currentGenerationCancellationToken === cancellationToken {
                currentGenerationCancellationToken = nil
            }
            if currentGenerationAssistantClientMessageID == streamingMessageID {
                currentGenerationAssistantClientMessageID = nil
            }
            currentGenerationTask = nil
        }

        do {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            let modelReasoning = (try? await aiConfigCenter.effectiveScenarioBundles())?
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName) ?? .unknown
            stateStore.setError(nil, for: threadID)
            let snapshot = try await sendMessageUseCase.executeRegenerateReply(
                threadID: threadID,
                memberID: memberContextStore.context.selectedMemberID,
                selectedChatModelName: flags.selectedChatModelName,
                assistantClientMessageID: streamingMessageID,
                inference: inference,
                modelReasoning: modelReasoning,
                cancellationToken: cancellationToken,
                onAssistantPartial: nil,
                cachedMemberCompleteData: cachedMemberCompleteData
            )

            if let finalRow = await loadChatThreadsUseCase.execute(threadID: snapshot.thread.id) {
                stateStore.upsertThreadListItem(finalRow)
            }
            let finalMessages = await loadChatMessagesUseCase.execute(threadID: snapshot.thread.id)
            stateStore.setMessages(finalMessages, for: snapshot.thread.id)
            stateStore.setError(nil, for: snapshot.thread.id)
            logger.info(
                "重新生成回答完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
        } catch is CancellationError {
            stateStore.setError(nil, for: threadID)
            await finalizeInterruptedAssistantMessageIfNeeded(
                threadID: threadID,
                assistantClientMessageID: streamingMessageID
            )
            logger.info("重新生成回答已中断，thread=\(shortID(threadID))", module: .general)
        } catch {
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
                    && message.blocks.contains(where: { $0.kind == .error || $0.kind == .assistantStatusCard })
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

    private func finalizeInterruptedAssistantMessageIfNeeded(
        threadID: UUID,
        assistantClientMessageID: UUID
    ) async {
        guard finalizedInterruptedAssistantMessageIDs.contains(assistantClientMessageID) == false else { return }

        let didFinalize = await sendMessageUseCase.finalizeInterruptedAssistantMessage(
            statusCard: ChatAssistantStatusCardPayload(
                type: .interrupted,
                message: L10n.text("chat.generation.interrupted")
            ),
            assistantClientMessageID: assistantClientMessageID
        )
        guard didFinalize else { return }
        finalizedInterruptedAssistantMessageIDs.insert(assistantClientMessageID)
        let latest = await loadChatMessagesUseCase.execute(threadID: threadID)
        stateStore.setMessages(latest, for: threadID)
        stateStore.requestScrollToBottom(for: threadID)
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
        let statusCard = ChatAssistantStatusCardPayload(type: .sendFailed, message: message)
        appendLocalMessage(
            threadID: threadID,
            role: .assistant,
            blocks: [
                ChatMessageBlock(
                    kind: .assistantStatusCard,
                    assistantStatusCard: statusCard
                )
            ],
            deliveryState: .failed,
            clientMessageID: assistantClientMessageID,
            source: "chat.error"
        )
    }

    private func appendLocalMessage(
        threadID: UUID,
        role: ChatMessageRole,
        blocks: [ChatMessageBlock],
        deliveryState: ChatDeliveryState,
        clientMessageID: UUID = UUID(),
        source: String
    ) {
        var messages = stateStore.persistedMessages(for: threadID)
        let existingMessage = messages.first(where: { $0.clientMessageID == clientMessageID })
        let local = ChatMessage(
            id: existingMessage?.id ?? clientMessageID,
            threadID: threadID,
            role: role,
            blocks: blocks,
            clientMessageID: clientMessageID,
            serverMessageID: existingMessage?.serverMessageID,
            deliveryState: deliveryState,
            createdAt: existingMessage?.createdAt ?? Date(),
            serverUpdatedAt: existingMessage?.serverUpdatedAt,
            modelName: existingMessage?.modelName ?? role.rawValue
        )
        if let existingIndex = messages.firstIndex(where: { $0.clientMessageID == clientMessageID }) {
            messages[existingIndex] = local
            stateStore.setMessages(messages, for: threadID)
        } else {
            messages.append(local)
            stateStore.setMessages(messages, for: threadID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.chatRepository.upsertLocalMessage(local)
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
            status: old.status,
            revision: old.revision + 1,
            orderKey: old.orderKey,
            createdAt: old.createdAt,
            updatedAt: Date()
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

        await updatePendingMemberToolCard(threadID: threadID, message: message, cardID: card.id) {
            $0.selectedMemberID = memberID
            $0.status = .completed
            $0.arguments["member_id"] = String(memberID)
            $0.resultText = L10n.text("tool.result.request_member_selection.completed")
            $0.updatedAt = Date()
        }
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

    // MARK: - 对话内营养卡片写入 Apple 健康

    func handleNutritionCardAction(
        threadID: UUID,
        message: ChatMessage,
        action: ChatNutritionCardAction
    ) async {
        switch action {
        case .writeToHealth(let blockID, let cardID):
            await writeNutritionCardToHealth(
                threadID: threadID,
                message: message,
                blockID: blockID,
                cardID: cardID
            )
        }
    }

    private func writeNutritionCardToHealth(
        threadID: UUID,
        message: ChatMessage,
        blockID: UUID,
        cardID: UUID
    ) async {
        guard let block = message.blocks.first(where: { $0.id == blockID }),
              case .nutritionCards(let payload) = block.payload,
              let cardIndex = payload.cards.firstIndex(where: { $0.id == cardID }),
              payload.cards[cardIndex].isWritten == false else {
            return
        }

        let card = payload.cards[cardIndex]
        savingNutritionCardIDs.insert(cardID)
        defer { savingNutritionCardIDs.remove(cardID) }

        do {
            _ = try await SparkHealthTool.shared.writeNutritionData(card.sparkNutritionCard())
            notificationClient.success(
                L10n.text("chat.nutrition_card.written.toast"),
                title: nil,
                source: "chat.nutrition.write"
            )
            var updatedCards = payload.cards
            updatedCards[cardIndex].isWritten = true
            updatedCards[cardIndex].writtenAt = Date()
            let updatedBlock = block.replacingPayload(
                .nutritionCards(ChatNutritionCardsPayload(cards: updatedCards)),
                status: block.status
            )
            await persistNutritionCardsBlock(
                threadID: threadID,
                message: message,
                block: updatedBlock
            )
        } catch {
            logger.error("营养卡片写入 Apple 健康失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("chat.nutrition_card.write_failed.title"),
                source: "chat.nutrition.write"
            )
        }
    }

    private func persistNutritionCardsBlock(
        threadID: UUID,
        message: ChatMessage,
        block: ChatMessageBlock
    ) async {
        let didApply = await chatRepository.upsertMessageBlock(
            clientMessageID: message.clientMessageID,
            block: block,
            markPendingForSync: true
        )
        guard didApply else { return }
        if let updatedMessage = message.replacingBlock(block) {
            stateStore.updateMessages([updatedMessage], for: threadID)
        }
    }

    // MARK: - 对话内结构化医疗卡片保存

    func handleStructuredHealthCardAction(
        threadID: UUID,
        message: ChatMessage,
        action: ChatStructuredHealthCardAction
    ) async {
        switch action {
        case .save(let blockID, let item):
            await saveStructuredHealthCard(threadID: threadID, message: message, blockID: blockID, item: item)
        case .setMember(let blockID, let item, let memberID):
            await updateStructuredHealthCardMember(
                threadID: threadID,
                message: message,
                blockID: blockID,
                item: item,
                memberID: memberID
            )
        }
    }

    private func saveStructuredHealthCard(
        threadID: UUID,
        message: ChatMessage,
        blockID: UUID,
        item: ChatStructuredHealthCardItem
    ) async {
        guard let output = makeStructuredHealthCardSaveOutput(for: item) else { return }
        await saveWithCardId(item.id, rawTrace: item.rawTrace) {
            output
        } onSuccess: { receipt in
            await bindStructuredHealthCardAttachmentIfNeeded(item: item, output: output, receipt: receipt)
            await updateStructuredHealthCardsBlob(
                threadID: threadID,
                message: message,
                blockID: blockID,
                item: item
            ) {
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
        onSuccess: (MedicalDocumentSaveReceipt) async -> Void
    ) async {
        // 标记卡片正在保存中，防止重复保存
        savingStructuredHealthCardIDs.insert(cardID)
        // 方法结束时移除保存中标记（无论成功失败）
        defer { savingStructuredHealthCardIDs.remove(cardID) }
        
        do {
            // 构建保存所需的输出数据
            let output = try buildOutput()
            // 执行保存用例
            let receipt = try await saveTypedMedicalDocumentUseCase.execute(output: output)
            
            // 保存成功：提示用户 + 打印日志 + 执行成功回调
            notificationClient.success(
                L10n.text("chat.medical_card.saved.toast"),
                title: nil,
                source: "chat.medical.save"
            )
            logger.info("对话医疗卡片已保存 trace=\(rawTrace)", module: .general)
            await onSuccess(receipt)
        } catch {
            // 保存失败：打印错误日志 + 提示用户
            logger.error("对话医疗卡片保存失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.medical.save")
        }
    }

    private func bindStructuredHealthCardAttachmentIfNeeded(
        item: ChatStructuredHealthCardItem,
        output: MedicalDocumentTypedExtractionOutput,
        receipt: MedicalDocumentSaveReceipt
    ) async {
        guard let ossFileId = item.ossFileId else { return }
        let businessType = structuredHealthCardAttachmentBusinessType(for: output.envelope.typeResolution.kind)
        do {
            _ = try await fileTransferService.updateBusinessBinding(
                fileID: ossFileId,
                businessType: businessType,
                businessID: "\(receipt.recordID)"
            )
            logger.info(
                "对话医疗卡片附件已绑定 fileID=\(ossFileId), businessType=\(businessType), businessID=\(receipt.recordID)",
                module: .medical
            )
        } catch {
            logger.error(
                "对话医疗卡片附件绑定失败 fileID=\(ossFileId), businessType=\(businessType), businessID=\(receipt.recordID), error=\(error.localizedDescription)",
                module: .medical
            )
        }
    }

    private func structuredHealthCardAttachmentBusinessType(for kind: MedicalDocumentKind) -> String {
        switch kind {
        case .auto:
            return "medical_document"
        case .caseDocument:
            return "medical_case"
        case .healthExamReport:
            return "health_exam_report"
        case .medicalReport:
            return "examination_report"
        case .prescription:
            return "prescription_batch"
        case .medicationPlan:
            return "medication_plan"
        case .medicineBox:
            return "medicine_box"
        }
    }

    private func makeStructuredHealthCardSaveOutput(for item: ChatStructuredHealthCardItem) -> MedicalDocumentTypedExtractionOutput? {
        guard let memberID = validatedCardMemberID(item.memberId) else {
            return nil
        }
        guard let data = item.draftJson.data(using: .utf8) else {
            notificationClient.error(L10n.text("chat.medical_card.error.decode"), title: nil, source: "chat.medical.save")
            return nil
        }

        switch item {
        case .medicationPlan:
            guard let draft = decodeStructuredHealthCardDraft(MedicationPlanRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .medicationPlan,
                rawText: item.rawTrace,
                typedResult: .medicationPlan([draft]),
                extractedJSON: item.draftJson
            )
        case .medicineBox:
            guard let draft = decodeStructuredHealthCardDraft(MedicineBoxRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .medicineBox,
                rawText: item.rawTrace,
                typedResult: .medicineBoxes([draft]),
                extractedJSON: item.draftJson
            )
        case .prescription:
            if let drafts = decodeStructuredHealthCardDraft([PrescriptionRecognitionDraft].self, from: data) {
                return makeStructuredHealthCardSaveOutput(
                    memberID: memberID,
                    kind: .prescription,
                    rawText: item.rawTrace,
                    typedResult: .prescription(drafts),
                    extractedJSON: item.draftJson
                )
            }
            guard let draft = decodeStructuredHealthCardDraft(PrescriptionRecognitionDraft.self, from: data) else { return nil }
            return makeStructuredHealthCardSaveOutput(
                memberID: memberID,
                kind: .prescription,
                rawText: item.rawTrace,
                typedResult: .prescription([draft]),
                extractedJSON: item.draftJson
            )
        case .examReport:
            if let report = try? JSONDecoder.default.decode(MedicalReportRecognitionDraft.self, from: data) {
                return makeStructuredHealthCardSaveOutput(
                    memberID: memberID,
                    kind: .medicalReport,
                    rawText: item.rawTrace,
                    typedResult: .medicalReport([report]),
                    extractedJSON: item.draftJson
                )
            }
            if let health = try? JSONDecoder.default.decode(HealthExamRecognitionDraft.self, from: data) {
                return makeStructuredHealthCardSaveOutput(
                    memberID: memberID,
                    kind: .healthExamReport,
                    rawText: item.rawTrace,
                    typedResult: .healthExamReport(health),
                    extractedJSON: item.draftJson
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
                extractedJSON: item.draftJson
            )
        }
    }

    private func decodeStructuredHealthCardDraft<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard let draft = try? JSONDecoder.default.decode(type, from: data) else {
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
        blockID: UUID,
        item: ChatStructuredHealthCardItem,
        memberID: Int?
    ) async {
        await updateStructuredHealthCardsBlob(
            threadID: threadID,
            message: message,
            blockID: blockID,
            item: item
        ) {
            $0.updateMember(item, memberId: memberID)
        }
    }

    // MARK: - 卡片状态标记（更新消息 blocks 中卡片状态）

    private func updateStructuredHealthCardsBlob(
        threadID: UUID,
        message: ChatMessage,
        blockID: UUID,
        item: ChatStructuredHealthCardItem,
        mutate: (inout StructuredHealthCardsBlob) -> Void
    ) async {
        guard let updatedBlock = replacingStructuredHealthCardsBlock(
            in: message.blocks,
            blockID: blockID,
            item: item,
            mutate: mutate
        ) else {
            return
        }
        await persistStructuredHealthCardsBlock(
            threadID: threadID,
            message: message,
            block: updatedBlock
        )
    }

    // MARK: - Blocks 持久化与同步

    /// 持久化更新后的 pending 成员工具等整包 blocks（非结构化健康卡片单块路径）。
    private func persistStructuredBlocks(threadID: UUID, message: ChatMessage, blocks: [ChatMessageBlock]) async {
        await updateChatMessageBlocksUseCase.execute(
            clientMessageID: message.clientMessageID,
            blocks: blocks,
            markPendingForSync: true
        )
    }

    /// 单条 `structuredHealthCards` 块写入本地并标记待同步（走 block_updates）。
    private func persistStructuredHealthCardsBlock(
        threadID: UUID,
        message: ChatMessage,
        block: ChatMessageBlock
    ) async {
        let didApply = await chatRepository.upsertMessageBlock(
            clientMessageID: message.clientMessageID,
            block: block,
            markPendingForSync: true
        )
        guard didApply else { return }
        if let updatedMessage = message.replacingBlock(block) {
            stateStore.updateMessages([updatedMessage], for: threadID)
        }
    }

    /// 按 block id 更新对应 `structuredHealthCards` 载荷（同条消息可有多块）。
    private func replacingStructuredHealthCardsBlock(
        in blocks: [ChatMessageBlock],
        blockID: UUID,
        item: ChatStructuredHealthCardItem,
        mutate: (inout StructuredHealthCardsBlob) -> Void
    ) -> ChatMessageBlock? {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              blocks[index].kind == .structuredHealthCards,
              var blob = blocks[index].structuredHealthCards,
              blob.contains(item: item) else {
            return nil
        }
        mutate(&blob)
        return blocks[index].replacingPayload(
            .structuredHealthCards(blob),
            status: blocks[index].status
        )
    }
}

extension ChatDetailViewModel: MemberCompleteDataFetching {}

extension ChatMessage {
    fileprivate func replacingBlock(_ block: ChatMessageBlock) -> ChatMessage? {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return nil }
        var nextBlocks = blocks
        nextBlocks[index] = block
        return ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            blocks: nextBlocks,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: serverUpdatedAt,
            isTombstone: isTombstone,
            modelName: modelName
        )
    }
}
