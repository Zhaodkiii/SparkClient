import SwiftUI
import UIKit
import Combine

struct ChatView: View {
    private enum ParameterCardKind: Hashable {
        case temperature
        case topP
        case maxTokens
        case maxMessages
        case imageDeliveryMode
    }
    
    /// 初始进入该 ChatView 时的 threadID；运行时当前会话请使用 currentThreadID（CHAT-000030）。
    let threadID: UUID
    /// CHAT-000030：详情页内部当前会话 ID（右上角新建对话后原地切换，不经过导航栈）。
    @State private var activeThreadID: UUID
    /// CHAT-000030：右上角新建对话防重入标记。
    @State private var isCreatingThreadInDetail = false
    /// CHAT-000030：详情页内部新建对话失败提示文案（nil 表示无错误）。
    @State private var detailThreadCreationError: String?
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let autoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator?
    /// 仅 fullScreenCover 场景注入；普通 NavigationStack 场景保持系统返回按钮。
    let onClose: (() -> Void)?
    /// 引导卡片滑块 → 健康首页 destination（CHAT-000025）；nil 时滑块降级为纯展示。
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    @State private var hasLoaded = false
    @StateObject private var uiStateStore = ChatMessageUIStateStore()
    @StateObject private var messageNavigationCoordinator = ChatMessageNavigationCoordinator()
    private let actionStateHandle = ChatMessageActionStateHandle(ChatMessageActionState())
    @StateObject private var speechHelper = ChatSpeechHelper()
    @State private var showClearChatConfirmation = false
    @State private var showNoAvailableChatModelAlert = false
    @State private var showCloseChatConfirmation = false
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.hanlin.rawValue
    private let logger: Logger = ConsoleLogger()
    private static let cardActionSnapshotStorageKeyPrefix = "chat.view.card_action_snapshot."
    static let inlineErrorClientMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")!
    @State private var activeParameterCard: ParameterCardKind?
    @State private var overlaySettings = ChatThreadGenerationSettings(
        currentModelName: nil,
        temperature: nil,
        topP: 1.0,
        maxTokens: nil,
        maxMessages: 20,
        rolePrompt: "",
        imageDeliveryMode: .directMultimodal
    )
    @State private var sendsOriginalImagesToAITemporarily = false
    @State private var isShowingGuideAddDevice = false
    
    /// CHAT-000030：详情页运行时唯一业务 thread 来源（右上角新建后原地切换）。
    private var currentThreadID: UUID {
        activeThreadID
    }

    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: currentThreadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(currentThreadID.uuidString)|\(name)"
    }

    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .hanlin
    }

    /// CHAT-000030：消息列表必须按 currentThreadID 读取，不能跟随全局 selectedMessages，
    /// 避免局部 activeThreadID 与全局 selectedThreadID 短暂不同步时显示错线程消息。
    private var visibleMessages: [ChatMessage] {
        stateStore.conversationListItems(for: currentThreadID).filter { uiStateStore.isDeleted($0.id) == false }
    }

    private var hasMoreMessages: Bool {
        stateStore.hasMoreMessages(for: currentThreadID)
    }

    private var isLoadingMoreMessages: Bool {
        stateStore.isLoadingMoreMessages(for: currentThreadID)
    }
    
    var body: some View {
        AnyView(configuredLayout)
    }

    init(
        threadID: UUID,
        stateStore: ChatStateStore,
        listViewModel: ChatListViewModel,
        detailViewModel: ChatDetailViewModel,
        knowledgeDependencies: KnowledgeFeatureDependencies,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        taskManager: TaskManager,
        homeViewModel: HomeViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        autoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator? = nil,
        guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.threadID = threadID
        _activeThreadID = State(initialValue: threadID)
        self.stateStore = stateStore
        self.listViewModel = listViewModel
        self.detailViewModel = detailViewModel
        self.knowledgeDependencies = knowledgeDependencies
        self.knowledgeViewModel = knowledgeViewModel
        self.taskManager = taskManager
        self.homeViewModel = homeViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.autoSmallTaskCoordinator = autoSmallTaskCoordinator
        self.guideHomeDestinationBuilder = guideHomeDestinationBuilder
        self.onClose = onClose
        self.stateStore.setComposerStartupPreferences(aiSettingsViewModel.snapshot.chatComposerStartupPreferences)
    }
    
    private var baseLayout: some View {
        messageList
    }
    
    @ViewBuilder
    private var composerChrome: some View {
        switch composerStyle {
        case .signal:
            ChatComposerView(
                threadID: currentThreadID,
                stateStore: stateStore,
                onSend: {
                    sendCurrentDraftIfChatModelAvailable()
                },
                onCancel: {
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.cancelCurrentGeneration()
                },
                onAttachmentsPicked: { attachments in
                    detailViewModel.enqueueComposerAttachments(attachments, for: currentThreadID)
                },
                onRemoveAttachment: { attachmentID in
                    detailViewModel.removeComposerAttachment(id: attachmentID, for: currentThreadID)
                },
                smallTasks: composerAssociatedSmallTasks,
                onSmallTaskTapped: { task in
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.startSmallTask(
                        task,
                        sendsOriginalImagesToAI: sendsOriginalImagesToAITemporarily
                    )
                }
            )
        case .hanlin:
            HanlinChatComposerView(
                threadID: currentThreadID,
                modelReasoning: detailViewModel.reasoningToolbarContext,
                stateStore: stateStore,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                aiSettingsViewModel: aiSettingsViewModel,
                boundMemberID: stateStore.selectedThread?.memberID,
                modelRows: detailViewModel.chatScenarioModels,
                smallTasks: composerAssociatedSmallTasks,
                initialCompleteData: homeViewModel.dashboard?.medical.completeData,
                memberCompleteDataFetcher: detailViewModel,
                medicalQueryAPI: detailViewModel.sparkMedicalQueryAPI,
                fileTransferService: detailViewModel.attachmentFileTransferService,
                onSend: {
                    sendCurrentDraftIfChatModelAvailable()
                },
                onCancel: {
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.cancelCurrentGeneration()
                },
                onSmallTaskTapped: { task in
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.startSmallTask(
                        task,
                        sendsOriginalImagesToAI: sendsOriginalImagesToAITemporarily
                    )
                },
                onAttachmentsPicked: { attachments in
                    detailViewModel.enqueueComposerAttachments(attachments, for: currentThreadID)
                },
                onRemoveAttachment: { attachmentID in
                    detailViewModel.removeComposerAttachment(id: attachmentID, for: currentThreadID)
                },
                onSetMemberBinding: { memberID in
                    Task { await detailViewModel.updateThreadMemberBinding(memberID, for: currentThreadID) }
                },
                onMaxHealthRefsReached: {
                    detailViewModel.notifyAskReportMaxRefsReached()
                },
                onPresentAskReportPicker: {
                    detailViewModel.presentAskReportPicker(for: currentThreadID, memberID: stateStore.selectedThread?.memberID)
                },
                onPersistSelectedChatModel: { modelName in
                    Task { await detailViewModel.updateThreadModel(modelName, for: currentThreadID) }
                }
            )
        }
        
    }
    
    // MARK: - 编辑器相关计算属性
    /// 获取当前编辑器选中的模型行（优先级：草稿选中 > 会话当前模型 > 默认模型 > 第一个模型）
    private var selectedComposerModelRow: AIScenarioRemoteModelRow? {
        selectedComposerModelRow(for: currentThreadID)
    }

    /// CHAT-000030：按 threadID 解析选中模型行（详情页内部切换 thread 后不得沿用旧 thread 的草稿/模型）。
    private func selectedComposerModelRow(for threadID: UUID) -> AIScenarioRemoteModelRow? {
        // 1. 优先取编辑器草稿中记录的选中模型名称（去空格）
        let selectedName = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // 2. 如果有选中名称，在场景模型列表中匹配对应行
        if selectedName.isEmpty == false,
           let row = detailViewModel.chatScenarioModels.first(where: { $0.name == selectedName }) {
            return row
        }
        
        // 3. 未选中则取当前会话绑定的模型名称匹配
        if let threadModel = stateStore.threadItems.first(where: { $0.id == threadID })?.thread.currentModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           threadModel.isEmpty == false,
           let row = detailViewModel.chatScenarioModels.first(where: { $0.name == threadModel }) {
            return row
        }
        
        // 4. 最后兜底：默认模型 或 列表第一个模型
        return detailViewModel.chatScenarioModels.first(where: \.isDefault) ?? detailViewModel.chatScenarioModels.first
    }
    
    /// 获取当前选中模型【关联绑定的小任务列表】
    private var composerAssociatedSmallTasks: [SmallTask] {
        // 无选中模型返回空数组
        guard let row = selectedComposerModelRow else { return [] }
        
        // 1. 把小任务列表转成【code -> task】的字典，方便快速查找（统一格式化编码）
        let tasksByCode = detailViewModel.chatSmallTasks.reduce(into: [String: SmallTask]()) { result, task in
            result[normalizeTaskCode(task.code)] = task
        }
        
        // 2. 根据模型关联的 taskCodes，从字典中取出对应的小任务（过滤不存在的）
        return row.relatedTaskCodes.compactMap { tasksByCode[normalizeTaskCode($0)] }
    }
    
    // MARK: - 工具方法
    /// 标准化任务编码：去空格 + 转小写（确保匹配不受大小写/空格影响）
    private func normalizeTaskCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    
    private var configuredLayout: some View {
        lifecycleLayout
    }
    
    private var navigationDecoratedLayout: some View {
        
        baseLayout
            .navigationTitle(stateStore.selectedThread?.listDisplayTitle ?? L10n.text("chat.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $messageNavigationCoordinator.activeSmallTaskPayload) { payload in
                SmallTaskDetailView(
                    viewModel: aiSettingsViewModel,
                    taskCode: payload.code,
                    source: payload.source
                )
            }
            .navigationDestination(item: $messageNavigationCoordinator.activeTaskDetailMode) { mode in
                TaskDetailView(
                    memberID: nil,
                    taskManager: taskManager,
                    knowledgeDependencies: knowledgeDependencies,
                    knowledgeViewModel: knowledgeViewModel,
                    mode: mode,
                    onPreviewSave: { previewContext, card in
                        guard let message = messageForNavigation(clientMessageID: previewContext.messageClientID) else {
                            throw NSError(
                                domain: "ChatMessageNavigation",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "无法找到任务卡对应的会话消息"]
                            )
                        }
                        return try await detailViewModel.saveTaskCardPreview(
                            threadID: previewContext.threadID,
                            message: message,
                            card: card
                        )
                    },
                    onPreviewEdit: { previewContext, result in
                        guard let message = messageForNavigation(clientMessageID: previewContext.messageClientID) else { return }
                        await detailViewModel.updateTaskCardPreviewDraft(
                            threadID: previewContext.threadID,
                            message: message,
                            cardID: previewContext.card.id,
                            result: result
                        )
                    }
                )
            }
            .navigationDestination(item: $messageNavigationCoordinator.activeStructuredHealthPreview) { context in
                ChatStructuredHealthCardPreviewDestination(
                    context: context,
                    memberContextStore: homeViewModel.memberContextStoreForBinding,
                    medicalQueryAPI: detailViewModel.sparkMedicalQueryAPI,
                    fileTransferService: detailViewModel.attachmentFileTransferService,
                    notificationClient: detailViewModel.chatNotificationClient,
                    cachedCompleteData: detailViewModel.cachedMemberCompleteData,
                    onDraftUpdated: { updatedItem in
                        guard let message = messageForNavigation(clientMessageID: context.messageClientID) else { return }
                        Task {
                            await detailViewModel.updateStructuredHealthCardPreviewDraft(
                                threadID: context.threadID,
                                message: message,
                                blockID: context.blockID,
                                item: updatedItem
                            )
                        }
                    }
                )
            }
            .navigationDestination(item: $messageNavigationCoordinator.activeWeatherConfigCard) { _ in
                AIWeatherToolSettingsView(viewModel: aiSettingsViewModel)
                    .hidesMainTabBarWhenPushed()
            }
            .navigationDestination(item: $messageNavigationCoordinator.activeToolConsentDetailTarget) { target in
                if let descriptor = ToolModelEgressConsentPolicy.descriptor(for: target.toolName) {
                    AIToolConsentDetailView(viewModel: aiSettingsViewModel, descriptor: descriptor)
                } else {
                    List {
                        Section {
                            Text(SparkToolName.displayName(for: target.toolName))
                                .font(.body.weight(.semibold))
                            Text(target.toolName)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("当前工具没有可配置的授权详情。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("授权详情")
                }
            }
            .safeAreaInset(edge: .bottom) {
                composerChrome
            }
//            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .bottom) {
                parameterOverlay
                
            }
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if stateStore.isSending {
                                showCloseChatConfirmation = true
                            } else {
                                onClose()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .accessibilityLabel(L10n.text("common.close", fallback: "关闭"))
                        .accessibilityHint(
                            L10n.text(
                                "chat.health_resource_conversation.close.hint",
                                fallback: "关闭当前全屏对话"
                            )
                        )
                    }
                }

                // CHAT-000030：新建对话按钮与设置菜单合并到同一 ToolbarItemGroup，
                // 避免 .topBarTrailing / .navigationBarTrailing 混用在部分 iOS 版本排列不稳定。
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // CHAT-000030：详情页右上角新建对话（当前详情内部切换 thread，不跳转）。
                    Button {
                        Task { await createThreadInsideCurrentChat() }
                    } label: {
                        if isCreatingThreadInDetail {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.bubble")
                        }
                    }
                    .disabled(isCreatingThreadInDetail || stateStore.isSending)
                    .accessibilityLabel(L10n.text("chat.thread.new", fallback: "新建对话"))

                    Menu {
                        Menu(L10n.text("chat.settings.menu"), systemImage: "slider.horizontal.3") {
                            Button {
                                presentParameterCard(.temperature)
                            } label: {
                                Label(L10n.text("chat.settings.temperature.title"), systemImage: "thermometer.variable")
                            }
                            Button {
                                presentParameterCard(.topP)
                            } label: {
                                Label(L10n.text("chat.settings.top_p.title"), systemImage: "percent")
                            }
                            Button {
                                presentParameterCard(.maxTokens)
                            } label: {
                                Label(L10n.text("chat.settings.max_tokens.title"), systemImage: "textformat.size")
                            }
                            Button {
                                presentParameterCard(.maxMessages)
                            } label: {
                                Label(L10n.text("chat.settings.max_messages.title"), systemImage: "message.badge")
                            }
                            Button {
                                presentParameterCard(.imageDeliveryMode)
                            } label: {
                                Label(L10n.text("chat.settings.image_delivery.title"), systemImage: "photo.on.rectangle.angled")
                            }
                        }
                        Divider()
                        
                        Menu(L10n.text("chat.management.records_menu"), systemImage: "bubble.left.and.bubble.right") {
                            Button {
                                presentParameterCard(.imageDeliveryMode)
                            } label: {
                                Label(L10n.text("chat.image_delivery.menu"), systemImage: "photo.on.rectangle.angled")
                            }
                            Button {
                                presentParameterCard(.maxMessages)
                            } label: {
                                Label(L10n.text("chat.management.context_window"), systemImage: "rectangle.compress.vertical")
                            }
                            Button {
                                exportChatRecordsToDebugLog()
                            } label: {
                                Label(L10n.text("chat.management.export_records"), systemImage: "square.and.arrow.up")
                            }
                            Button {
                                logger.warning("聊天记录导入暂未接入，thread=\(currentThreadID.uuidString)", module: .general)
                            } label: {
                                Label(L10n.text("chat.management.import_records"), systemImage: "square.and.arrow.down")
                            }
                            Button(role: .destructive) {
                                showClearChatConfirmation = true
                            } label: {
                                Label(L10n.text("chat.management.clear_records"), systemImage: "eraser.line.dashed")
                            }
                            Button {
                                logDebugInfo()
                            } label: {
                                Label(L10n.text("chat.management.print_debug_info"), systemImage: "doc.text.magnifyingglass")
                            }
                            
                        }
                        Divider()
                        
                        Menu(L10n.text("chat.keyboard.settings.menu"), systemImage: "keyboard") {
                            Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                                Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                                Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                            }
                        }
                        Divider()
                        
                        
                        Button {
                            presentSystemMessageSettings()
                        } label: {
                            Label(L10n.text("chat.system_message.menu"), systemImage: "text.bubble")
                        }
                        
                    } label: {
                        Label(L10n.text("chat.settings.menu"), systemImage: "slider.horizontal.3")
                    }

                }
            }
    }
    
    private var initialLoadLayout: some View {
        navigationDecoratedLayout
            .task {
                guard hasLoaded == false else { return }
                hasLoaded = true
                listViewModel.selectThread(currentThreadID)
                restoreCardActionSnapshotIfNeeded(forceReload: true)
            }
            .onChange(of: threadID) { newValue in
                // 导航栈复用同 identity 但传入不同 threadID 时同步局部 activeThreadID
                guard newValue != activeThreadID else { return }
                switchDetailThread(from: activeThreadID, to: newValue)
            }
    }
    
    private var statePersistenceLayoutStep1: some View {
        initialLoadLayout
            .onChange(of: uiStateStore.savedKnowledgeCardIDs) { _ in
                persistCardActionSnapshot()
            }
            .onChange(of: uiStateStore.savedMessageIDs) { _ in
                persistCardActionSnapshot()
            }
    }
    
    private var statePersistenceLayout: some View {
        statePersistenceLayoutStep1
            .onChange(of: uiStateStore.ignoredTaskCardIDs) { _ in
                persistCardActionSnapshot()
            }
            .onChange(of: uiStateStore.createdTaskCardIDs) { _ in
                persistCardActionSnapshot()
            }
    }
    
    private var lifecycleLayout: some View {
        statePersistenceLayout
            .onAppear {
                detailViewModel.updateCachedMemberCompleteData(homeViewModel.dashboard?.medical.completeData)
                detailViewModel.updateToolInteractionPreferences(aiSettingsViewModel.snapshot.chatToolInteractionPreferences)
                stateStore.setComposerStartupPreferences(aiSettingsViewModel.snapshot.chatComposerStartupPreferences)
            }
            .onChange(of: homeViewModel.dashboard?.medical.completeData) { data in
                detailViewModel.updateCachedMemberCompleteData(data)
            }
            .onChange(of: aiSettingsViewModel.snapshot.chatToolInteractionPreferences) { preferences in
                detailViewModel.updateToolInteractionPreferences(preferences)
            }
            .onChange(of: aiSettingsViewModel.snapshot.chatComposerStartupPreferences) { preferences in
                stateStore.setComposerStartupPreferences(preferences)
            }
            // CHAT-000030：以 currentThreadID 作为生命周期 key，右上角新建后原地重启新 thread 初始化链路。
            .task(id: currentThreadID) {
                // 固定本轮 ID，避免 await 期间用户再次新建导致后续步骤串到别的 thread
                let id = currentThreadID
                logger.info(
                    "chat.detail.thread_switch.task_start thread=\(String(id.uuidString.prefix(8))) marker=\(stateStore.isThreadMarkedAsNewlyCreated(id))",
                    module: .general
                )
                listViewModel.selectThread(id)
                if let initialModel = await detailViewModel.refreshChatModelPicker(for: id) {
                    if stateStore.composerDraft(for: id).runtimeFlags.selectedChatModelName == nil {
                        stateStore.setSelectedChatModelName(initialModel, for: id)
                    }
                }
                await detailViewModel.refreshThreadImageDeliveryMode(for: id)
                await detailViewModel.loadMessagesIfNeeded(for: id, lockBottomViewport: true)
                logger.info(
                    "chat.detail.thread_switch.messages_loaded thread=\(String(id.uuidString.prefix(8))) count=\(stateStore.persistedMessages(for: id).count)",
                    module: .general
                )
                // CHAT-000029：默认绑定已在 thread 创建阶段前置完成，页面不再补绑。
                // 新建链路：保持新建标记（阻止并发 repair）→ 幂等插入 guide card → 启动生成 → 清除标记；
                // 重新进入旧对话：只做 guide 卡片异常状态修复，绝不生成。
                if stateStore.isThreadMarkedAsNewlyCreated(id) {
                    let didInsertGuideCard = await detailViewModel.ensureFirstGuideCardInsertedForNewThreadIfNeeded(threadID: id)
                    if didInsertGuideCard {
                        await detailViewModel.startGuideQuestionGenerationForNewlyCreatedThread(threadID: id)
                    }
                    stateStore.clearThreadWasJustCreatedMarker(id)
                    logger.info(
                        "chat.detail.thread_switch.guide_ensured thread=\(String(id.uuidString.prefix(8))) inserted=\(didInsertGuideCard)",
                        module: .general
                    )
                } else {
                    await detailViewModel.repairGuideQuestionsForReenteredThreadIfNeeded(threadID: id)
                }
                await trySendAutoSmallTaskIfReady(for: id)
            }
            .task(id: reasoningRefreshId) {
                await detailViewModel.refreshReasoningToolbarContext(for: currentThreadID)
            }
            .sheet(
                item: Binding(
                    get: { detailViewModel.toolInteractionCoordinator.activePresentation },
                    set: { newValue in
                        guard newValue == nil else { return }
                        detailViewModel.clearToolPreviewRenderContext()
                        detailViewModel.toolInteractionCoordinator.dismissActivePresentationByUser()
                    }
                )
            ) { active in
                ToolInteractionPresentationSheet(
                    active: active,
                    coordinator: detailViewModel.toolInteractionCoordinator,
                    memberContextStore: homeViewModel.memberContextStoreForBinding,
                    stateStore: stateStore,
                    toolPreviewRenderContext: detailViewModel.toolPreviewRenderContext,
                    aiSettingsViewModel: aiSettingsViewModel,
                    initialCompleteData: homeViewModel.dashboard?.medical.completeData,
                    memberCompleteDataFetcher: detailViewModel,
                    onClearToolPreviewRenderContext: { detailViewModel.clearToolPreviewRenderContext() },
                    onSaveSystemMessage: { prompt, value in
                        Task {
                            await detailViewModel.updateThreadSystemPrompt(value, for: prompt.threadID)
                        }
                    },
                    onAskReportAppend: { _, refs in
                        detailViewModel.appendAskReportRefs(refs, for: currentThreadID)
                    },
                    onAskReportSetMemberBinding: { memberID in
                        Task { await detailViewModel.updateThreadMemberBinding(memberID, for: currentThreadID) }
                    },
                    onAskReportMaxRefsReached: {
                        detailViewModel.notifyAskReportMaxRefsReached()
                    }
                )
                .interactiveDismissDisabled(active.snapshot.requiresForcedSheetDismiss)
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatGuideBindHealthRequested)) { _ in
                isShowingGuideAddDevice = true
            }
            .sheet(isPresented: $isShowingGuideAddDevice) {
                NavigationStack {
                    ChatGuideAddDeviceSheet(
                        memberContextStore: homeViewModel.memberContextStoreForBinding
                    )
                }
                .onDisappear {
                    logger.info("chat.guide.metrics.binding_sheet_closed", module: .general)
                    NotificationCenter.default.post(name: .chatGuideHealthBindingDidChange, object: nil)
                }
            }
            .alert(L10n.text("chat.list.no_available_model.title"), isPresented: $showNoAvailableChatModelAlert) {
                Button(L10n.text("chat.list.no_available_model.action")) {
                    detailViewModel.toolInteractionCoordinator.presentAPIKeysSettings()
                }
                Button(L10n.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("chat.list.no_available_model.message"))
            }
            .alert(
                L10n.text(
                    "chat.health_resource_conversation.close.title",
                    fallback: "关闭对话？"
                ),
                isPresented: $showCloseChatConfirmation
            ) {
                Button(
                    L10n.text(
                        "chat.health_resource_conversation.close.continue",
                        fallback: "继续对话"
                    ),
                    role: .cancel
                ) {}
                Button(
                    L10n.text(
                        "chat.health_resource_conversation.close.stop",
                        fallback: "停止并关闭"
                    ),
                    role: .destructive
                ) {
                    detailViewModel.cancelCurrentGeneration()
                    onClose?()
                }
            } message: {
                Text(
                    L10n.text(
                        "chat.health_resource_conversation.close.message",
                        fallback: "当前回答仍在生成，停止后将关闭全屏对话。"
                    )
                )
            }
            .alert(L10n.text("chat.management.clear_confirm_title"), isPresented: $showClearChatConfirmation) {
                Button(L10n.text("common.cancel"), role: .cancel) {}
                Button(L10n.text("chat.management.clear_action"), role: .destructive) {
                    Task { await detailViewModel.clearMessages(for: currentThreadID) }
                }
            } message: {
                Text(L10n.text("chat.management.clear_confirm_message"))
            }
            // CHAT-000030：详情页内部新建对话失败提示（保留旧会话，不切换）
            .alert(
                L10n.text("chat.thread.create_failed", fallback: "新建对话失败"),
                isPresented: Binding(
                    get: { detailThreadCreationError != nil },
                    set: { if $0 == false { detailThreadCreationError = nil } }
                )
            ) {
                Button(L10n.text("common.ok", fallback: "好"), role: .cancel) {}
            } message: {
                Text(detailThreadCreationError ?? "")
            }
    }

    /// CHAT-000030：自动小任务显式按 threadID 触发，避免详情页内部切换后发送到旧 thread。
    private func trySendAutoSmallTaskIfReady(for threadID: UUID) async {
        guard let autoSmallTaskCoordinator else { return }
        guard let row = selectedComposerModelRow(for: threadID) else { return }
        await autoSmallTaskCoordinator.trySendIfNeeded(
            threadID: threadID,
            selectedModelRow: row,
            stateStore: stateStore,
            detailViewModel: detailViewModel
        )
    }

    @ViewBuilder
    private var messageList: some View {
        switch aiSettingsViewModel.snapshot.chatConversationUIPreferences.architecture {
        case .uiKit:
            ChatConversationMessageListContainer(
                threadID: currentThreadID,
                stateStore: stateStore,
                detailViewModel: detailViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                uiStateStore: uiStateStore,
                speechHelper: speechHelper,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                navigationCoordinator: messageNavigationCoordinator,
                taskManager: taskManager,
                logger: logger,
                actionStateHandle: actionStateHandle,
                conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
                visibleMessages: visibleMessages,
                hasMoreMessages: hasMoreMessages,
                isLoadingMoreMessages: isLoadingMoreMessages,
                lockBottomViewport: stateStore.isBottomViewportLocked(for: currentThreadID),
                scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: currentThreadID),
                guideHomeDestinationBuilder: guideHomeDestinationBuilder
            )
        case .swiftUI:
            ChatSwiftUIConversationView(
                threadID: currentThreadID,
                stateStore: stateStore,
                detailViewModel: detailViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                uiStateStore: uiStateStore,
                speechHelper: speechHelper,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                navigationCoordinator: messageNavigationCoordinator,
                taskManager: taskManager,
                logger: logger,
                actionStateHandle: actionStateHandle,
                conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
                uiPreferences: aiSettingsViewModel.snapshot.chatConversationUIPreferences,
                visibleMessages: visibleMessages,
                hasMoreMessages: hasMoreMessages,
                isLoadingMoreMessages: isLoadingMoreMessages,
                lockBottomViewport: stateStore.isBottomViewportLocked(for: currentThreadID),
                scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: currentThreadID),
                guideHomeDestinationBuilder: guideHomeDestinationBuilder
            )
        }
    }

    private func messageForNavigation(clientMessageID: UUID) -> ChatMessage? {
        visibleMessages.first { $0.clientMessageID == clientMessageID }
    }
    
    private var cardActionSnapshotStorageKey: String {
        Self.cardActionSnapshotStorageKeyPrefix + currentThreadID.uuidString.lowercased()
    }
    
    private func restoreCardActionSnapshotIfNeeded(forceReload: Bool = false) {
        if forceReload {
            uiStateStore.applyCardActionSnapshot(.empty, forceReload: true)
        }
        guard let data = UserDefaults.standard.data(forKey: cardActionSnapshotStorageKey) else { return }
        guard let snapshot = try? JSONDecoder.default.decode(CardActionSnapshot.self, from: data) else { return }
        uiStateStore.applyCardActionSnapshot(snapshot, forceReload: false)
    }
    
    private func persistCardActionSnapshot() {
        let snapshot = uiStateStore.makeCardActionSnapshot()
        guard let data = try? JSONEncoder.default.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cardActionSnapshotStorageKey)
    }
    
    @ViewBuilder
    private var parameterOverlay: some View {
        if let card = activeParameterCard {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeParameterCard = nil
                    }
                
                parameterCard(for: card)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: card)
        }
    }
    
    @ViewBuilder
    private func parameterCard(for kind: ParameterCardKind) -> some View {
        switch kind {
        case .temperature:
            ChatThreadSettingCard(
                title: L10n.text("chat.settings.temperature.title"),
                subtitle: L10n.text("chat.settings.temperature.subtitle"),
                systemImage: "thermometer.variable",
                options: temperatureOptions,
                selection: Binding(
                    get: { overlaySettings.temperature },
                    set: { updateOverlayTemperature($0) }
                )
            )
        case .topP:
            ChatThreadSettingCard(
                title: L10n.text("chat.settings.top_p.title"),
                subtitle: L10n.text("chat.settings.top_p.subtitle"),
                systemImage: "percent",
                options: topPOptions,
                selection: Binding(
                    get: { overlaySettings.topP },
                    set: { updateOverlaySetting(topP: $0) }
                )
            )
        case .maxTokens:
            ChatThreadSettingCard(
                title: L10n.text("chat.settings.max_tokens.title"),
                subtitle: L10n.text("chat.settings.max_tokens.subtitle"),
                systemImage: "textformat.size",
                options: maxTokenOptions,
                selection: Binding(
                    get: { overlaySettings.maxTokens },
                    set: { updateOverlayMaxTokens($0) }
                )
            )
        case .maxMessages:
            ChatThreadSettingCard(
                title: L10n.text("chat.settings.max_messages.title"),
                subtitle: L10n.text("chat.settings.max_messages.subtitle"),
                systemImage: "message.badge",
                options: maxMessageOptions,
                selection: Binding(
                    get: { overlaySettings.maxMessages },
                    set: { updateOverlaySetting(maxMessages: $0) }
                )
            )
        case .imageDeliveryMode:
            VStack(spacing: 12) {
                ChatThreadSettingCard(
                    title: L10n.text("chat.settings.image_delivery.title"),
                    subtitle: L10n.text("chat.settings.image_delivery.subtitle"),
                    systemImage: "photo.on.rectangle.angled",
                    options: imageDeliveryOptions,
                    selection: Binding(
                        get: { overlaySettings.imageDeliveryMode },
                        set: { updateOverlaySetting(imageDeliveryMode: $0) }
                    )
                )
                ChatThreadToggleSettingCard(
                    title: L10n.text("chat.settings.send_original_images_to_ai.title"),
                    subtitle: L10n.text("chat.settings.send_original_images_to_ai.subtitle"),
                    systemImage: "photo.badge.checkmark",
                    isOn: Binding(
                        get: { sendsOriginalImagesToAITemporarily },
                        set: { sendsOriginalImagesToAITemporarily = $0 }
                    )
                )
            }
        }
    }
    
    private var temperatureOptions: [ChatThreadSettingOption<Double?>] {
        [
            ChatThreadSettingOption(
                id: "temp-default",
                value: nil,
                title: L10n.text("chat.settings.model_default"),
                detail: L10n.text("chat.settings.temperature.detail.model_default")
            )
        ] + stride(from: 0.1, through: 2.0, by: 0.1).map { raw in
            let value = Double(round(raw * 10) / 10)
            return ChatThreadSettingOption(
                id: String(format: "temp-%.1f", value),
                value: value,
                title: String(format: "%.1f", value),
                detail: value < 0.7
                ? L10n.text("chat.settings.temperature.detail.low")
                : (value > 1.2 ? L10n.text("chat.settings.temperature.detail.high") : L10n.text("chat.settings.temperature.detail.medium"))
            )
        }
    }
    
    private var topPOptions: [ChatThreadSettingOption<Double>] {
        stride(from: 0.1, through: 1.0, by: 0.1).map { raw in
            let value = Double(round(raw * 10) / 10)
            return ChatThreadSettingOption(
                id: String(format: "top-p-%.1f", value),
                value: value,
                title: String(format: "%.1f", value),
                detail: value < 0.5
                ? L10n.text("chat.settings.top_p.detail.low")
                : (value > 0.8 ? L10n.text("chat.settings.top_p.detail.high") : L10n.text("chat.settings.top_p.detail.medium"))
            )
        }
    }
    
    private var maxTokenOptions: [ChatThreadSettingOption<Int?>] {
        [
            ChatThreadSettingOption(
                id: "tokens-default",
                value: nil,
                title: L10n.text("chat.settings.model_default"),
                detail: L10n.text("chat.settings.max_tokens.detail.model_default")
            )
        ] + [256, 512, 1024, 2048, 4096, 8192, 16384, 32768].map { value in
            ChatThreadSettingOption(
                id: "tokens-\(value)",
                value: value,
                title: "\(value)",
                detail: L10n.format("chat.settings.max_tokens.detail", value)
            )
        }
    }
    
    private var maxMessageOptions: [ChatThreadSettingOption<Int>] {
        [5, 10, 20, 30, 40, 50, 60].map { value in
            ChatThreadSettingOption(
                id: "messages-\(value)",
                value: value,
                title: "\(value)",
                detail: L10n.format("chat.settings.max_messages.detail", value)
            )
        }
    }
    
    private var imageDeliveryOptions: [ChatThreadSettingOption<ChatThreadImageDeliveryMode>] {
        [
            ChatThreadSettingOption(
                id: ChatThreadImageDeliveryMode.directMultimodal.rawValue,
                value: .directMultimodal,
                title: L10n.text("chat.image_delivery.direct"),
                detail: detailViewModel.currentModelSupportsMultimodal
                ? L10n.text("chat.settings.image_delivery.detail.direct")
                : L10n.text("chat.image_delivery.unavailable_hint")
            ),
            ChatThreadSettingOption(
                id: ChatThreadImageDeliveryMode.localOCR.rawValue,
                value: .localOCR,
                title: L10n.text("chat.image_delivery.ocr_only"),
                detail: L10n.text("chat.settings.image_delivery.detail.ocr")
            )
        ]
    }
    
    private func presentParameterCard(_ kind: ParameterCardKind) {
        let thread = stateStore.selectedThread ?? ChatThread(title: L10n.text("chat.default_thread_title"))
        overlaySettings = ChatThreadGenerationSettings(thread: thread)
        if activeParameterCard == kind {
            activeParameterCard = nil
        } else {
            activeParameterCard = kind
        }
    }
    
    private func presentSystemMessageSettings() {
        activeParameterCard = nil
        let thread = stateStore.threadItems.first(where: { $0.id == currentThreadID })?.thread
            ?? ChatThread(title: L10n.text("chat.default_thread_title"))
        let row = selectedComposerModelRow
        let isAgent = row?.identity == AIModelIdentity.agent.rawValue
        let prompt = SystemMessageSettingsPrompt(
            threadID: currentThreadID,
            sessionPrompt: thread.rolePrompt,
            defaultPrompt: PromptLocalizer().chatSystemPrompt(),
            modelDisplayName: row?.displayTitle ?? thread.currentModelName ?? L10n.text("chat.composer.model.default"),
            isAgentModel: isAgent,
            agentPrompt: isAgent ? row?.systemPrompt : nil,
            promptTemplates: detailViewModel.chatPromptTemplates
        )
        detailViewModel.presentSystemMessageSettings(prompt: prompt)
    }
    
    private func sendCurrentDraftIfChatModelAvailable() {
        KeyboardDismissHelper.dismissKeyboard()
        guard detailViewModel.chatScenarioModels.isEmpty == false else {
            showNoAvailableChatModelAlert = true
            return
        }
        detailViewModel.startSendingCurrentDraft(
            sendsOriginalImagesToAI: sendsOriginalImagesToAITemporarily
        )
    }
    
    private func updateOverlaySetting(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        maxMessages: Int? = nil,
        imageDeliveryMode: ChatThreadImageDeliveryMode? = nil
    ) {
        let next = ChatThreadGenerationSettings(
            currentModelName: overlaySettings.currentModelName,
            temperature: temperature ?? overlaySettings.temperature,
            topP: topP ?? overlaySettings.topP,
            maxTokens: maxTokens ?? overlaySettings.maxTokens,
            maxMessages: maxMessages ?? overlaySettings.maxMessages,
            rolePrompt: overlaySettings.rolePrompt,
            imageDeliveryMode: imageDeliveryMode ?? overlaySettings.imageDeliveryMode
        )
        guard next != overlaySettings else { return }
        overlaySettings = next
        Task {
            await detailViewModel.updateThreadGenerationSettings(next, for: currentThreadID)
        }
    }
    
    private func updateOverlayTemperature(_ temperature: Double?) {
        let next = ChatThreadGenerationSettings(
            currentModelName: overlaySettings.currentModelName,
            temperature: temperature,
            topP: overlaySettings.topP,
            maxTokens: overlaySettings.maxTokens,
            maxMessages: overlaySettings.maxMessages,
            rolePrompt: overlaySettings.rolePrompt,
            imageDeliveryMode: overlaySettings.imageDeliveryMode
        )
        persistOverlaySettings(next)
    }
    
    private func updateOverlayMaxTokens(_ maxTokens: Int?) {
        let next = ChatThreadGenerationSettings(
            currentModelName: overlaySettings.currentModelName,
            temperature: overlaySettings.temperature,
            topP: overlaySettings.topP,
            maxTokens: maxTokens,
            maxMessages: overlaySettings.maxMessages,
            rolePrompt: overlaySettings.rolePrompt,
            imageDeliveryMode: overlaySettings.imageDeliveryMode
        )
        persistOverlaySettings(next)
    }
    
    private func persistOverlaySettings(_ next: ChatThreadGenerationSettings) {
        guard next != overlaySettings else { return }
        overlaySettings = next
        Task {
            await detailViewModel.updateThreadGenerationSettings(next, for: currentThreadID)
        }
    }
    
    private func exportChatRecordsToDebugLog() {
        logDebugInfo()
    }

    // MARK: - CHAT-000030 详情页内部新建对话与 thread 切换

    /// CHAT-000030：右上角新建对话入口。
    /// 不做任何 Navigation push/pop，创建成功后在当前详情容器内部切换到新 thread。
    @MainActor
    private func createThreadInsideCurrentChat() async {
        // 防重入：创建中/发送中直接忽略，避免连点产生多个 thread
        guard isCreatingThreadInDetail == false else { return }
        guard stateStore.isSending == false else { return }
        let oldThreadID = currentThreadID
        isCreatingThreadInDetail = true
        detailThreadCreationError = nil
        defer { isCreatingThreadInDetail = false }

        logger.info(
            "chat.detail.new_thread_button.tap current=\(String(oldThreadID.uuidString.prefix(8))) isSending=\(stateStore.isSending)",
            module: .general
        )

        guard let newThreadID = await listViewModel.createThread() else {
            detailThreadCreationError = L10n.text("chat.thread.create_failed", fallback: "新建对话失败，请稍后再试")
            logger.warning(
                "chat.detail.new_thread_button.create_failed current=\(String(oldThreadID.uuidString.prefix(8)))",
                module: .general
            )
            return
        }

        logger.info(
            "chat.detail.new_thread_button.create_success old=\(String(oldThreadID.uuidString.prefix(8))) new=\(String(newThreadID.uuidString.prefix(8)))",
            module: .general
        )
        switchDetailThread(from: oldThreadID, to: newThreadID)
    }

    /// CHAT-000030：当前详情内部切换 thread（同步全局 selectedThreadID、
    /// 持久化旧 thread 卡片动作快照并恢复新 thread 快照、清理临时 UI 状态）。
    @MainActor
    private func switchDetailThread(from oldThreadID: UUID, to newThreadID: UUID) {
        guard oldThreadID != newThreadID else { return }
        logger.info(
            "chat.detail.thread_switch.begin old=\(String(oldThreadID.uuidString.prefix(8))) new=\(String(newThreadID.uuidString.prefix(8)))",
            module: .general
        )
        // 先用旧 key 持久化当前卡片动作快照，再切 activeThreadID
        persistCardActionSnapshot()
        activeThreadID = newThreadID
        stateStore.setSelectedThreadID(newThreadID)
        logger.info(
            "chat.detail.thread_switch.active_set old=\(String(oldThreadID.uuidString.prefix(8))) new=\(String(newThreadID.uuidString.prefix(8))) selected=\(stateStore.selectedThreadID?.uuidString.prefix(8) ?? "nil")",
            module: .general
        )
        // 关闭参数弹层/重置消息内导航，避免保存或展示串到旧 thread
        activeParameterCard = nil
        messageNavigationCoordinator.reset()
        // 恢复新 thread 的卡片动作快照（forceReload 清掉旧 thread 遗留 UI 状态）
        restoreCardActionSnapshotIfNeeded(forceReload: true)
    }
    
    private func logDebugInfo() {
        let messages = stateStore.conversationListItems(for: currentThreadID)
        let userMessages = messages.filter { $0.role == .user }.count
        let assistantMessages = messages.filter { $0.role == .assistant }.count
        let thread = stateStore.threadItems.first(where: { $0.id == currentThreadID })?.thread
        let modelName = thread?.currentModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = (modelName?.isEmpty == false) ? modelName! : "未设置"
        let summary = """
        ChatView 对话调试信息:
        - ThreadID: \(currentThreadID.uuidString)
        - 标题: \(thread?.listDisplayTitle ?? L10n.text("chat.default_thread_title"))
        - 选择模型: \(selectedModel)
        - 消息总数: \(messages.count) (用户: \(userMessages), 助手: \(assistantMessages))
        - 参数: temperature=\(thread?.temperature ?? 0), topP=\(thread?.topP ?? 0), maxTokens=\(thread?.maxTokens ?? 0), maxMessages=\(thread?.maxMessages ?? 0)
        - 图片送达方式(本会话): \(thread?.imageDeliveryMode.rawValue ?? "-")
        - 是否正在发送: \(stateStore.isSending)
        - 最后错误: \(stateStore.errorMessage(for: currentThreadID) ?? "无")
        """
        logger.debug(summary, module: .general)
        
        let iso = ISO8601DateFormatter()
        let sortedMessages = messages.sorted { $0.createdAt < $1.createdAt }
        let payload: [[String: Any]] = sortedMessages.map { message in
            let attachments = message.blocks
                .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
                .flatMap(\.attachments)
            let contentPreview = message.blocks
                .compactMap(\.text)
                .joined(separator: "\n")
            var row: [String: Any] = [
                "id": message.id.uuidString,
                "client_message_id": message.clientMessageID.uuidString,
                "role": message.role.rawValue,
                "delivery_state": message.deliveryState.rawValue,
                "created_at": iso.string(from: message.createdAt),
                "content_preview": String(contentPreview.prefix(300)),
                "attachments_count": attachments.count,
                "blocks_count": message.blocks.count
            ]
            if let attachmentsObject = encodableToJSONObject(attachments) {
                row["attachments"] = attachmentsObject
            }
            if let blocksObject = encodableToJSONObject(message.blocks) {
                row["blocks"] = blocksObject
            }
            if let deepThought = message.blocks.last(where: { $0.kind == .deepThought })?.deepThoughtCard,
               let reasoning = deepThought.reasoningContent,
               reasoning.isEmpty == false {
                row["reasoning_preview"] = String(reasoning.suffix(200))
            }
            if let model = message.modelName, model.isEmpty == false {
                row["model_name"] = model
            }
            return row
        }
        let exportData: [String: Any] = [
            "thread_id": currentThreadID.uuidString,
            "title": thread?.listDisplayTitle ?? "",
            "debug_time": iso.string(from: Date()),
            "messages": payload
        ]
        if let data = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            logger.debug("ChatView 对话内容 JSON:\n\(json)", module: .general)
        } else {
            logger.warning("ChatView 对话内容序列化为 JSON 失败", module: .general)
        }
    }
    
    private func encodableToJSONObject<T: Encodable>(_ value: T) -> Any? {
        let encoder = JSONEncoder.default
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    
}

/// 对话列表内的健康设备管理 sheet，复用设备模块已有的成员与绑定管理流程。
private struct ChatGuideAddDeviceSheet: View {
    let memberContextStore: MemberContextStore

    init(memberContextStore: MemberContextStore) {
        self.memberContextStore = memberContextStore
    }

    var body: some View {
        MyDevicesView(memberContextStore: memberContextStore)
    }
}

/// 消息列表容器：缓存 refresh coordinator，避免 Representable 存储 async closure。
private struct ChatConversationMessageListContainer: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var navigationCoordinator: ChatMessageNavigationCoordinator
    let taskManager: TaskManager
    let logger: Logger
    let actionStateHandle: ChatMessageActionStateHandle
    let conversationAppearance: ChatConversationAppearancePreferences
    let visibleMessages: [ChatMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    @StateObject private var refreshCoordinator: ConversationMessageListRefreshCoordinator

    init(
        threadID: UUID,
        stateStore: ChatStateStore,
        detailViewModel: ChatDetailViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        knowledgeDependencies: KnowledgeFeatureDependencies,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        uiStateStore: ChatMessageUIStateStore,
        speechHelper: ChatSpeechHelper,
        memberContextStore: MemberContextStore,
        navigationCoordinator: ChatMessageNavigationCoordinator,
        taskManager: TaskManager,
        logger: Logger,
        actionStateHandle: ChatMessageActionStateHandle,
        conversationAppearance: ChatConversationAppearancePreferences,
        visibleMessages: [ChatMessage],
        hasMoreMessages: Bool,
        isLoadingMoreMessages: Bool,
        lockBottomViewport: Bool,
        scrollToBottomRequestGeneration: UInt64,
        guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil
    ) {
        self.threadID = threadID
        self.stateStore = stateStore
        self.detailViewModel = detailViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.knowledgeDependencies = knowledgeDependencies
        self.knowledgeViewModel = knowledgeViewModel
        self.uiStateStore = uiStateStore
        self.speechHelper = speechHelper
        self.memberContextStore = memberContextStore
        self.navigationCoordinator = navigationCoordinator
        self.taskManager = taskManager
        self.logger = logger
        self.actionStateHandle = actionStateHandle
        self.conversationAppearance = conversationAppearance
        self.visibleMessages = visibleMessages
        self.hasMoreMessages = hasMoreMessages
        self.isLoadingMoreMessages = isLoadingMoreMessages
        self.lockBottomViewport = lockBottomViewport
        self.scrollToBottomRequestGeneration = scrollToBottomRequestGeneration
        self.guideHomeDestinationBuilder = guideHomeDestinationBuilder
        _refreshCoordinator = StateObject(
            wrappedValue: ConversationMessageListRefreshCoordinator(
                threadID: threadID,
                detailViewModel: detailViewModel
            )
        )
    }

    var body: some View {
        ConversationMessageListRepresentable(
            threadID: threadID,
            stateStore: stateStore,
            detailViewModel: detailViewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            knowledgeDependencies: knowledgeDependencies,
            knowledgeViewModel: knowledgeViewModel,
            uiStateStore: uiStateStore,
            speechHelper: speechHelper,
            memberContextStore: memberContextStore,
            navigationCoordinator: navigationCoordinator,
            taskManager: taskManager,
            logger: logger,
            actionStateHandle: actionStateHandle,
            conversationAppearance: conversationAppearance,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: lockBottomViewport,
            scrollToBottomRequestGeneration: scrollToBottomRequestGeneration,
            guideHomeDestinationBuilder: guideHomeDestinationBuilder,
            onCommand: { command in
                switch command {
                case .loadMore:
                    Task { await detailViewModel.loadMoreMessages(for: threadID) }
                }
            },
            refreshHandler: refreshCoordinator,
            conversationListLayoutNonce: refreshCoordinator.layoutNonce
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatScrollDismissesKeyboardInteractively()
    }
}
