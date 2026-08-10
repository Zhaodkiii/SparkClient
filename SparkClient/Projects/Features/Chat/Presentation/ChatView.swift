import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers

struct ChatView: View {
    private enum ParameterCardKind: Hashable {
        case temperature
        case topP
        case maxTokens
        case maxMessages
        case imageDeliveryMode
    }
    
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    
    @State private var hasLoaded = false
    @StateObject private var uiStateStore = ChatMessageUIStateStore()
    private let actionStateHandle = ChatMessageActionStateHandle(ChatMessageActionState())
    @StateObject private var speechHelper = ChatSpeechHelper()
    @State private var showCaptureFileImporter = false
    @State private var showClearChatConfirmation = false
    @State private var showNoAvailableChatModelAlert = false
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
    
    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(threadID.uuidString)|\(name)"
    }
    
    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .hanlin
    }
    
    private var visibleMessages: [ChatMessage] {
        stateStore.selectedMessages.filter { uiStateStore.isDeleted($0.id) == false }
    }
    
    private var hasMoreMessages: Bool {
        stateStore.hasMoreMessages(for: threadID)
    }
    
    private var isLoadingMoreMessages: Bool {
        stateStore.isLoadingMoreMessages(for: threadID)
    }
    
    var body: some View {
        AnyView(configuredLayout)
    }
    
    private var baseLayout: some View {
        messageList
    }
    
    @ViewBuilder
    private var composerChrome: some View {
        switch composerStyle {
        case .signal:
            ChatComposerView(
                threadID: threadID,
                stateStore: stateStore,
                onSend: {
                    sendCurrentDraftIfChatModelAvailable()
                },
                onCancel: {
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.cancelCurrentGeneration()
                },
                onAttachmentsPicked: { attachments in
                    detailViewModel.enqueueComposerAttachments(attachments, for: threadID)
                },
                onRemoveAttachment: { attachmentID in
                    detailViewModel.removeComposerAttachment(id: attachmentID, for: threadID)
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
                threadID: threadID,
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
                    detailViewModel.enqueueComposerAttachments(attachments, for: threadID)
                },
                onRemoveAttachment: { attachmentID in
                    detailViewModel.removeComposerAttachment(id: attachmentID, for: threadID)
                },
                onSetMemberBinding: { memberID in
                    Task { await detailViewModel.updateThreadMemberBinding(memberID, for: threadID) }
                },
                onMaxHealthRefsReached: {
                    detailViewModel.notifyAskReportMaxRefsReached()
                },
                onPresentAskReportPicker: {
                    detailViewModel.presentAskReportPicker(for: threadID, memberID: stateStore.selectedThread?.memberID)
                },
                onPersistSelectedChatModel: { modelName in
                    Task { await detailViewModel.updateThreadModel(modelName, for: threadID) }
                }
            )
        }
        
    }
    
    // MARK: - 编辑器相关计算属性
    /// 获取当前编辑器选中的模型行（优先级：草稿选中 > 会话当前模型 > 默认模型 > 第一个模型）
    private var selectedComposerModelRow: AIScenarioRemoteModelRow? {
        // 1. 优先取编辑器草稿中记录的选中模型名称（去空格）
        let selectedName = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // 2. 如果有选中名称，在场景模型列表中匹配对应行
        if selectedName.isEmpty == false,
           let row = detailViewModel.chatScenarioModels.first(where: { $0.name == selectedName }) {
            return row
        }
        
        // 3. 未选中则取当前会话绑定的模型名称匹配
        if let threadModel = stateStore.selectedThread?.currentModelName?
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
            .safeAreaInset(edge: .bottom) {
                composerChrome
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .bottom) {
                parameterOverlay
                
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
                                logger.warning("聊天记录导入暂未接入，thread=\(threadID.uuidString)", module: .general)
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
                listViewModel.selectThread(threadID)
                await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
                restoreCardActionSnapshotIfNeeded(forceReload: true)
            }
            .onChange(of: threadID) { _ in
                activeParameterCard = nil
                restoreCardActionSnapshotIfNeeded(forceReload: true)
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
            }
            .onChange(of: homeViewModel.dashboard?.medical.completeData) { data in
                detailViewModel.updateCachedMemberCompleteData(data)
            }
            .onChange(of: aiSettingsViewModel.snapshot.chatToolInteractionPreferences) { preferences in
                detailViewModel.updateToolInteractionPreferences(preferences)
            }
            .task(id: threadID) {
                if let initialModel = await detailViewModel.refreshChatModelPicker(for: threadID) {
                    if stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName == nil {
                        stateStore.setSelectedChatModelName(initialModel, for: threadID)
                    }
                }
                await detailViewModel.refreshThreadImageDeliveryMode(for: threadID)
            }
            .task(id: reasoningRefreshId) {
                await detailViewModel.refreshReasoningToolbarContext(for: threadID)
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
                        detailViewModel.appendAskReportRefs(refs, for: threadID)
                    },
                    onAskReportSetMemberBinding: { memberID in
                        Task { await detailViewModel.updateThreadMemberBinding(memberID, for: threadID) }
                    },
                    onAskReportMaxRefsReached: {
                        detailViewModel.notifyAskReportMaxRefsReached()
                    }
                )
                .interactiveDismissDisabled(active.snapshot.requiresForcedSheetDismiss)
            }
            .alert(L10n.text("chat.list.no_available_model.title"), isPresented: $showNoAvailableChatModelAlert) {
                Button(L10n.text("chat.list.no_available_model.action")) {
                    detailViewModel.toolInteractionCoordinator.presentAPIKeysSettings()
                }
                Button(L10n.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("chat.list.no_available_model.message"))
            }
            .alert(L10n.text("chat.management.clear_confirm_title"), isPresented: $showClearChatConfirmation) {
                Button(L10n.text("common.cancel"), role: .cancel) {}
                Button(L10n.text("chat.management.clear_action"), role: .destructive) {
                    Task { await detailViewModel.clearMessages(for: threadID) }
                }
            } message: {
                Text(L10n.text("chat.management.clear_confirm_message"))
            }
    }
    
    @ViewBuilder
    private var messageList: some View {
        switch aiSettingsViewModel.snapshot.chatConversationUIPreferences.architecture {
        case .uiKit:
            ChatConversationMessageListContainer(
                threadID: threadID,
                stateStore: stateStore,
                detailViewModel: detailViewModel,
                uiStateStore: uiStateStore,
                speechHelper: speechHelper,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                taskManager: taskManager,
                logger: logger,
                actionStateHandle: actionStateHandle,
                conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
                visibleMessages: visibleMessages,
                hasMoreMessages: hasMoreMessages,
                isLoadingMoreMessages: isLoadingMoreMessages,
                lockBottomViewport: stateStore.isBottomViewportLocked(for: threadID),
                scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: threadID),
                showCaptureFileImporter: $showCaptureFileImporter
            )
        case .swiftUI:
            ChatSwiftUIConversationView(
                threadID: threadID,
                stateStore: stateStore,
                detailViewModel: detailViewModel,
                uiStateStore: uiStateStore,
                speechHelper: speechHelper,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                taskManager: taskManager,
                logger: logger,
                actionStateHandle: actionStateHandle,
                conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
                uiPreferences: aiSettingsViewModel.snapshot.chatConversationUIPreferences,
                visibleMessages: visibleMessages,
                hasMoreMessages: hasMoreMessages,
                isLoadingMoreMessages: isLoadingMoreMessages,
                lockBottomViewport: stateStore.isBottomViewportLocked(for: threadID),
                scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: threadID),
                showCaptureFileImporter: $showCaptureFileImporter
            )
        }
    }
    
    private var cardActionSnapshotStorageKey: String {
        Self.cardActionSnapshotStorageKeyPrefix + threadID.uuidString.lowercased()
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
        let thread = stateStore.selectedThread ?? ChatThread(title: L10n.text("chat.default_thread_title"))
        let row = selectedComposerModelRow
        let isAgent = row?.identity == AIModelIdentity.agent.rawValue
        let prompt = SystemMessageSettingsPrompt(
            threadID: threadID,
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
            await detailViewModel.updateThreadGenerationSettings(next, for: threadID)
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
            await detailViewModel.updateThreadGenerationSettings(next, for: threadID)
        }
    }
    
    private func exportChatRecordsToDebugLog() {
        logDebugInfo()
    }
    
    private func logDebugInfo() {
        let messages = stateStore.selectedMessages
        let userMessages = messages.filter { $0.role == .user }.count
        let assistantMessages = messages.filter { $0.role == .assistant }.count
        let thread = stateStore.selectedThread
        let modelName = thread?.currentModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = (modelName?.isEmpty == false) ? modelName! : "未设置"
        let summary = """
        ChatView 对话调试信息:
        - ThreadID: \(threadID.uuidString)
        - 标题: \(thread?.listDisplayTitle ?? L10n.text("chat.default_thread_title"))
        - 选择模型: \(selectedModel)
        - 消息总数: \(messages.count) (用户: \(userMessages), 助手: \(assistantMessages))
        - 参数: temperature=\(thread?.temperature ?? 0), topP=\(thread?.topP ?? 0), maxTokens=\(thread?.maxTokens ?? 0), maxMessages=\(thread?.maxMessages ?? 0)
        - 图片送达方式(本会话): \(thread?.imageDeliveryMode.rawValue ?? "-")
        - 是否正在发送: \(stateStore.isSending)
        - 最后错误: \(stateStore.errorMessage(for: threadID) ?? "无")
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
            "thread_id": threadID.uuidString,
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

/// 消息列表容器：缓存 refresh coordinator，避免 Representable 存储 async closure。
private struct ChatConversationMessageListContainer: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    let taskManager: TaskManager
    let logger: Logger
    let actionStateHandle: ChatMessageActionStateHandle
    let conversationAppearance: ChatConversationAppearancePreferences
    let visibleMessages: [ChatMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64
    @Binding var showCaptureFileImporter: Bool

    @StateObject private var refreshCoordinator: ConversationMessageListRefreshCoordinator

    init(
        threadID: UUID,
        stateStore: ChatStateStore,
        detailViewModel: ChatDetailViewModel,
        uiStateStore: ChatMessageUIStateStore,
        speechHelper: ChatSpeechHelper,
        memberContextStore: MemberContextStore,
        taskManager: TaskManager,
        logger: Logger,
        actionStateHandle: ChatMessageActionStateHandle,
        conversationAppearance: ChatConversationAppearancePreferences,
        visibleMessages: [ChatMessage],
        hasMoreMessages: Bool,
        isLoadingMoreMessages: Bool,
        lockBottomViewport: Bool,
        scrollToBottomRequestGeneration: UInt64,
        showCaptureFileImporter: Binding<Bool>
    ) {
        self.threadID = threadID
        self.stateStore = stateStore
        self.detailViewModel = detailViewModel
        self.uiStateStore = uiStateStore
        self.speechHelper = speechHelper
        self.memberContextStore = memberContextStore
        self.taskManager = taskManager
        self.logger = logger
        self.actionStateHandle = actionStateHandle
        self.conversationAppearance = conversationAppearance
        self.visibleMessages = visibleMessages
        self.hasMoreMessages = hasMoreMessages
        self.isLoadingMoreMessages = isLoadingMoreMessages
        self.lockBottomViewport = lockBottomViewport
        self.scrollToBottomRequestGeneration = scrollToBottomRequestGeneration
        _showCaptureFileImporter = showCaptureFileImporter
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
            uiStateStore: uiStateStore,
            speechHelper: speechHelper,
            memberContextStore: memberContextStore,
            taskManager: taskManager,
            logger: logger,
            actionStateHandle: actionStateHandle,
            conversationAppearance: conversationAppearance,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: lockBottomViewport,
            scrollToBottomRequestGeneration: scrollToBottomRequestGeneration,
            onCommand: { command in
                switch command {
                case .loadMore:
                    Task { await detailViewModel.loadMoreMessages(for: threadID) }
                case .captureOpenFiles:
                    showCaptureFileImporter = true
                }
            },
            refreshHandler: refreshCoordinator,
            conversationListLayoutNonce: refreshCoordinator.layoutNonce
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatScrollDismissesKeyboardInteractively()
        .fileImporter(
            isPresented: $showCaptureFileImporter,
            allowedContentTypes: [.pdf, .plainText, .image, .jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let attachments = await ChatComposerAttachmentImporter.importFiles(urls: urls)
                await MainActor.run {
                    detailViewModel.enqueueComposerAttachments(attachments, for: threadID)
                }
            }
        }
    }
}
