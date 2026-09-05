import SwiftUI
import UIKit
import Combine

enum ChatLeadingAction: Equatable {
    case close
    case home
}

/// CHAT-000054：医院会话身份判定状态。
/// 本地 scope 命中 → `.hospital`；服务端 context 404 → `.ordinary`；
/// context 请求失败 → `.failed`（阻断继承新建并展示错误，不降级为普通会话）。
private enum HospitalScopeResolution: Equatable {
    case undetermined
    case hospital(HospitalConversationScope)
    case ordinary
    case failed
}

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
    /// CHAT-000054：当前 thread 的医院会话身份判定结果。
    /// 引导卡插入、历史入口展示、新建继承都依赖该判定，进入页面后先完成判定再执行副作用。
    @State private var hospitalScopeResolution: HospitalScopeResolution = .undetermined
    @State private var showHospitalScopeResolutionFailure = false
    /// CHAT-000055：当前医院会话的能力（context 回源前为 nil，发送入口据此先回源再判定）。
    @State private var hospitalCapabilities: HospitalConversationCapabilities?
    /// CHAT-000057 38.6：context 回源的服务端实时服务状态（如 doctor_joined）。
    /// 统一 Manifest 未启用时，这是医生接管状态的唯一实时通道；nil 表示服务端未下发，不猜测。
    @State private var hospitalServiceStatus: ConversationServiceStatus?
    /// CHAT-000055：当前医院会话的知识 Manifest（仅用于展示/调试；同步由 coordinator 处理）。
    @State private var hospitalKnowledgeManifest: HospitalAgentKnowledgeManifest?
    /// CHAT-000055：医院会话发送被门禁拦截的提示文案（nil 表示无拦截）。
    @State private var hospitalSendBlockedMessage: String?
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let autoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator?
    /// 全屏入口的 leading action 语义；普通 push 场景为 nil。
    let leadingAction: ChatLeadingAction?
    /// 仅 fullScreenCover 场景注入；普通 NavigationStack 场景保持系统返回按钮。
    let onClose: (() -> Void)?
    /// 引导卡片滑块 → 健康首页 destination（CHAT-000025）；nil 时滑块降级为纯展示。
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil
    @Environment(\.hospitalCare) private var hospitalCare
    
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

    /// CHAT-000058：医院会话单项锁定模型行（配置缺失为 nil，此时不渲染可用选择器）。
    private var hospitalLockedComposerModelRow: AIScenarioRemoteModelRow? {
        guard case .hospital = hospitalScopeResolution else { return nil }
        return detailViewModel.hospitalComposerModelRows[currentThreadID]
    }

    /// CHAT-000058：医院会话后台校验失败/配置失效 → 输入区与发送整体禁用（C-013/C-014）。
    private var isHospitalRuntimeUnavailable: Bool {
        guard isTelemedicineConversation == false else { return false }
        guard case .hospital = hospitalScopeResolution else { return false }
        return detailViewModel.hospitalRuntimeUnavailableThreadIDs.contains(currentThreadID)
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

    // MARK: - CHAT-000057 unknown 会话门禁

    /// CHAT-000057 34.6：当前会话的统一投影项（仅统一消息列表开启时存在）。
    private var unifiedCurrentItem: UnifiedConversationListItem? {
        guard listViewModel.isUnifiedMessageListEnabled else { return nil }
        return listViewModel.unifiedItems.first { $0.threadID == currentThreadID }
    }

    /// unknown 会话的分类确认状态；非 unknown / 统一未开启为 nil（不产生门禁）。
    private var unifiedUnknownState: ConversationClassificationState? {
        guard let item = unifiedCurrentItem, item.conversationKind == .unknown else { return nil }
        return item.classificationState
    }

    /// CHAT-000057 34.4：unknown 确认期间输入区、附件、快捷问题与知识库同步全部禁用。
    private var isComposerBlockedByUnknownConfirmation: Bool {
        unifiedUnknownState != nil
    }

    /// 线上问诊一对一会话：统一投影 kind，或医院 scope 已带 consultationID。
    private var isTelemedicineConversation: Bool {
        if unifiedCurrentItem?.conversationKind == .telemedicine { return true }
        if case .hospital(let scope) = hospitalScopeResolution, scope.consultationID != nil {
            return true
        }
        return false
    }

    /// CHAT-000057 38.6/L1942：医生接管中（患者可发送，AI 不自动回复）。
    /// 仅适用于医生智能体；线上问诊本身就没有 AI，不能套用「医生接管中」文案。
    private var isDoctorTakeoverActive: Bool {
        if isTelemedicineConversation { return false }
        if unifiedCurrentItem?.conversationKind == .hospitalAgent,
           let capability = unifiedCurrentItem?.capability,
           capability.canSend, capability.canUseAI == false {
            return true
        }
        if hospitalServiceStatus?.isDoctorTakeover == true,
           hospitalCapabilities?.canSendMessage ?? true {
            return true
        }
        return false
    }

    /// 线上问诊待医生查看：pending_doctor / active / 尚未回源，且医生尚未接诊。
    private var isTelemedicineWaitingForDoctor: Bool {
        guard isTelemedicineConversation else { return false }
        if let status = hospitalServiceStatus {
            switch status {
            case .pendingDoctor, .active:
                return true
            case .doctorTakenOver, .doctorJoined, .ended, .suspended, .agentUnavailable,
                 .hospitalUnavailable, .consultationCompleted, .unsupported:
                return false
            }
        }
        return true
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
        leadingAction: ChatLeadingAction? = nil,
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
        self.leadingAction = leadingAction
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
                lockedHospitalModelRow: hospitalLockedComposerModelRow,
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
            .safeAreaInset(edge: .top, spacing: 0) {
                // CHAT-000057 34.6：unknown 会话顶部受控横幅（确认中 / 暂无法确认 + 重试）。
                if let state = unifiedUnknownState {
                    unifiedUnknownBanner(state: state)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    // CHAT-000058 C-013/C-014：后台校验失败 → 输入区上方固定“当前服务已不可用”，发送整体禁用。
                    if isHospitalRuntimeUnavailable {
                        hospitalRuntimeUnavailableBanner
                    } else if case .hospital = hospitalScopeResolution,
                       let capabilities = hospitalCapabilities,
                       capabilities.canSendMessage == false {
                        // CHAT-000055 Q27：智能体下架/会话只读时，输入区上方固定提示，发送入口同步禁用。
                        hospitalReadOnlyBanner(reason: capabilities.readOnlyReason)
                    } else if isTelemedicineWaitingForDoctor {
                        telemedicineWaitingBanner
                    } else if isDoctorTakeoverActive {
                        // CHAT-000057 38.6：医生接管中轻量提示（可发送，AI 不回复），与只读横幅互斥。
                        doctorTakeoverBanner
                    }
                    composerChrome
                        // CHAT-000057 34.4：unknown 确认期间输入区/附件/快捷问题整体禁用。
                        // CHAT-000058：医院配置失效时输入区/发送/重试同步禁用。
                        .disabled(isComposerBlockedByUnknownConfirmation || isHospitalRuntimeUnavailable)
                }
            }
        //            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .bottom) {
                parameterOverlay
                
            }
            .toolbar {
                if let onClose, let leadingAction {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if stateStore.isSending {
                                showCloseChatConfirmation = true
                            } else {
                                onClose()
                            }
                        } label: {
                            Image(systemName: leadingAction == .home ? "heart.fill" : "xmark.circle.fill")
                        }
                        .accessibilityLabel(
                            L10n.text(
                                leadingAction == .home ? "chat.home.return" : "common.close",
                                fallback: leadingAction == .home ? "返回首页" : "关闭"
                            )
                        )
                        .accessibilityHint(
                            L10n.text(
                                leadingAction == .home
                                ? "chat.home.return.hint"
                                : "chat.health_resource_conversation.close.hint",
                                fallback: leadingAction == .home
                                ? "关闭当前对话并返回健康首页"
                                : "关闭当前全屏对话"
                            )
                        )
                    }
                }
                
                // CHAT-000030：新建对话按钮与设置菜单合并到同一 ToolbarItemGroup，
                // 避免 .topBarTrailing / .navigationBarTrailing 混用在部分 iOS 版本排列不稳定。
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // CHAT-000054：医院会话隐藏“对话列表”入口，
                    // 医院 Thread 只能从院内名医目录或“最近咨询”进入。
                    if showsOrdinaryConversationListButton {
                        Button {
                            detailViewModel.toolInteractionCoordinator.presentConversationList()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel(
                            L10n.text("chat.conversation_list.open", fallback: "对话列表")
                        )
                    }
                    
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
#if DEBUG
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
#endif
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
            .onChange(of: homeViewModel.memberContextStoreForBinding.context.selectedMemberID) { _ in
                // CHAT-000056 Q7：成员切换后，旧成员的「有新消息」临时计数全部失效
                stateStore.clearAllUnseenRemoteMessageCounts()
                // CHAT-000058 C-022：成员切换清空医院专用会话状态（单项目录、固定配置、
                // 后台校验任务、不可用标记），并失效本账号 Keychain 专用配置引用；保留医院名医列表。
                detailViewModel.clearAllHospitalRuntimeSessions()
                if let hospitalCare, let accountID = listViewModel.signedInAccountID {
                    hospitalCare.runtimeConfigStore.clearAccount(accountID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatRealtimeThreadPullDidComplete)) { note in
                // CHAT-000056 Q8：定向拉取完成后刷新当前医院会话能力；下架/终结 → 输入立即只读。
                // Q7：仅当拉取结果属于当前成员时才允许更新当前 UI。
                guard let pulledThreadID = note.chatRealtimePulledThreadID,
                      pulledThreadID == currentThreadID,
                      case .hospital(let scope) = hospitalScopeResolution,
                      scope.memberID == homeViewModel.memberContextStoreForBinding.context.selectedMemberID else { return }
                Task {
                    await refreshHospitalConversationContext(threadID: pulledThreadID, scope: scope)
                    // CHAT-000057 38.6：拉取事件后同步刷新统一 Manifest，
                    // 使医生接管/取消接管等服务状态变化在已打开会话内即时生效（驱动 AI 回复门禁）。
                    await listViewModel.refreshUnifiedManifest(reason: .push)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatRealtimeThreadPullDidComplete)) { note in
                // CHAT-000057 26.5：前台可读会话的新到消息按既有实时链路即时确认已读（幂等）；
                // unknown/身份未确认时 UseCase 内部拒绝，不产生副作用。
                guard let pulledThreadID = note.chatRealtimePulledThreadID,
                      pulledThreadID == currentThreadID else { return }
                Task {
                    await markCurrentConversationReadIfAllowed(
                        threadID: pulledThreadID,
                        scopeResolution: hospitalScopeResolution
                    )
                }
            }
        // CHAT-000030：以 currentThreadID 作为生命周期 key，右上角新建后原地重启新 thread 初始化链路。
            .task(id: currentThreadID) {
                // 固定本轮 ID，避免 await 期间用户再次新建导致后续步骤串到别的 thread
                let id = currentThreadID
                let markedBeforeTake = stateStore.isThreadMarkedAsNewlyCreated(id)
                logger.info(
                    "CHAT-000061 thread_task_start thread=\(String(id.uuidString.prefix(8))) marker=\(markedBeforeTake)",
                    module: .general
                )
                let hospitalInitialMessages = stateStore.takeHospitalInitialMessages(for: id)
                logger.info(
                    "CHAT-000061 initial_messages_taken thread=\(String(id.uuidString.prefix(8))) present=\(hospitalInitialMessages != nil) count=\(hospitalInitialMessages?.count ?? 0)",
                    module: .general
                )
                listViewModel.selectThread(id)
                // CHAT-000058：本地 scope 命中的医院线程使用单项锁定目录；
                // 普通目录刷新不得修正其草稿选中态与线程模型（目录完全隔离，C-019）。
                let isHospitalThreadByLocalScope: Bool = {
                    guard let hospitalCare, let accountID = listViewModel.signedInAccountID else { return false }
                    return hospitalCare.scopeStore.scope(for: id, accountID: accountID) != nil
                }()
                if let initialModel = await detailViewModel.refreshChatModelPicker(
                    for: id,
                    skipSelectionCorrection: isHospitalThreadByLocalScope
                ) {
                    if isHospitalThreadByLocalScope == false,
                       stateStore.composerDraft(for: id).runtimeFlags.selectedChatModelName == nil {
                        stateStore.setSelectedChatModelName(initialModel, for: id)
                    }
                }
                await detailViewModel.refreshThreadImageDeliveryMode(for: id)
                await detailViewModel.loadMessagesIfNeeded(
                    for: id,
                    lockBottomViewport: true,
                    syncRemote: hospitalInitialMessages == nil
                )
                logger.info(
                    "CHAT-000061 local_messages_loaded thread=\(String(id.uuidString.prefix(8))) count=\(stateStore.persistedMessages(for: id).count) sync_remote=\(hospitalInitialMessages == nil)",
                    module: .general
                )
                if let hospitalInitialMessages {
                    logger.info(
                        "CHAT-000061 initial_messages_apply_start thread=\(String(id.uuidString.prefix(8))) count=\(hospitalInitialMessages.count)",
                        module: .general
                    )
                    // CHAT-000061：纳入当前 `.task(id:)` 的结构化初始化顺序。
                    // 初始消息入站并显式重读完成后再继续 scope/context 初始化，
                    // 避免嵌套 Task 在页面切换或生命周期变化时停在 apply_start。
                    await detailViewModel.applyHospitalInitialMessages(hospitalInitialMessages, threadID: id)
                    logger.info(
                        "CHAT-000061 initial_messages_apply_end thread=\(String(id.uuidString.prefix(8))) local_count=\(stateStore.persistedMessages(for: id).count)",
                        module: .general
                    )
                }
                logger.info(
                    "CHAT-000061 thread_task_after_local_load thread=\(String(id.uuidString.prefix(8))) count=\(stateStore.persistedMessages(for: id).count)",
                    module: .general
                )
                // CHAT-000054：先完成医院会话身份判定（本地 scope → 服务端 context 回源），
                // 再决定引导卡/修复/新建继承副作用，避免重装后医院会话被降级为普通会话。
                let scopeResolution = await resolveHospitalScope(for: id)
                hospitalScopeResolution = scopeResolution
                showHospitalScopeResolutionFailure = (scopeResolution == .failed)
                // CHAT-000055：医院会话进入后后台回源 context（能力 + 知识 Manifest），
                // 驱动发送门禁与知识同步；失败不降级、不阻断历史可读。
                if case .hospital(let scope) = scopeResolution {
                    let capturedScope = scope
                    Task { await refreshHospitalConversationContext(threadID: id, scope: capturedScope) }
                    // CHAT-000058：装载专用运行配置（内存 → Keychain → 服务端），
                    // Keychain 命中时先可用并注册后台静默校验；失败标记服务不可用并阻断发送。
                    if let accountID = listViewModel.signedInAccountID {
                        Task {
                            await detailViewModel.prepareHospitalRuntimeSession(
                                threadID: id,
                                scope: capturedScope,
                                accountID: accountID
                            )
                        }
                    }
                }
                // CHAT-000057 D-016/26.6：消息加载成功且身份确认后提交已读；
                // unknown/conflict/医院身份未确认不提交（26.3），幂等可重复。
                await markCurrentConversationReadIfAllowed(threadID: id, scopeResolution: scopeResolution)
                // CHAT-000057 38.6：进入会话后台刷新 Manifest（single-flight），
                // 获取最新服务状态（如医生接管 doctor_taken_over），驱动发送链路的 AI 回复门禁。
                await listViewModel.refreshUnifiedManifest(reason: .threadOpenConfirmation)
                // CHAT-000029：默认绑定已在 thread 创建阶段前置完成，页面不再补绑。
                // 新建链路：保持新建标记（阻止并发 repair）→ 幂等插入 guide card → 启动生成 → 清除标记；
                // 重新进入旧对话：只做 guide 卡片异常状态修复，绝不生成。
                if stateStore.isThreadMarkedAsNewlyCreated(id) {
                    let didInsertGuideCard: Bool
                    if case .ordinary = scopeResolution {
                        didInsertGuideCard = await detailViewModel.ensureFirstGuideCardInsertedForNewThreadIfNeeded(threadID: id)
                    } else {
                        // 医院会话或身份未明：不插入普通引导卡，避免降级副作用。
                        didInsertGuideCard = false
                    }
                    if didInsertGuideCard {
                        await detailViewModel.startGuideQuestionGenerationForNewlyCreatedThread(threadID: id)
                    }
                    stateStore.clearThreadWasJustCreatedMarker(id)
                    logger.info(
                        "chat.detail.thread_switch.guide_ensured thread=\(String(id.uuidString.prefix(8))) inserted=\(didInsertGuideCard)",
                        module: .general
                    )
                } else {
                    if case .ordinary = scopeResolution {
                        await detailViewModel.repairGuideQuestionsForReenteredThreadIfNeeded(threadID: id)
                    }
                }
                await trySendAutoSmallTaskIfReady(for: id)
            }
            .task(id: reasoningRefreshId) {
                await detailViewModel.refreshReasoningToolbarContext(for: currentThreadID)
            }
            .sheet(item: toolInteractionPresentationBinding) { active in
                toolInteractionSheetContent(active)
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
                        fallback: leadingAction == .home ? "停止并返回首页" : "停止并关闭"
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
        // CHAT-000054：医院会话身份校验失败提示（不降级普通会话，提供重试）。
            .alert(
                L10n.text("chat.hospital_scope.failed.title", fallback: "无法确认院内会话身份"),
                isPresented: $showHospitalScopeResolutionFailure
            ) {
                Button(L10n.text("common.retry", fallback: "重试")) {
                    Task { await retryHospitalScopeResolution() }
                }
                Button(L10n.text("common.cancel", fallback: "取消"), role: .cancel) {}
            } message: {
                Text(L10n.text(
                    "chat.hospital_scope.failed.message",
                    fallback: "当前会话的医院身份校验失败，请检查网络后重试。"
                ))
            }
        // CHAT-000055：医院会话发送门禁拦截提示（不发送、不重发、不转普通 AI）。
            .alert(
                L10n.text("chat.hospital.send_blocked.title", fallback: "暂时无法发送"),
                isPresented: Binding(
                    get: { hospitalSendBlockedMessage != nil },
                    set: { if $0 == false { hospitalSendBlockedMessage = nil } }
                )
            ) {
                Button(L10n.text("common.ok", fallback: "好"), role: .cancel) {}
            } message: {
                Text(hospitalSendBlockedMessage ?? "")
            }
    }

    /// 所有工具交互（包括对话列表）统一使用此绑定驱动单一 Sheet。
    private var toolInteractionPresentationBinding: Binding<ToolInteractionCoordinator.ActivePresentation?> {
        Binding(
            get: { detailViewModel.toolInteractionCoordinator.activePresentation },
            set: { newValue in
                guard newValue == nil else { return }
                detailViewModel.clearToolPreviewRenderContext()
                detailViewModel.toolInteractionCoordinator.dismissActivePresentationByUser()
            }
        )
    }

    @ViewBuilder
    private func toolInteractionSheetContent(
        _ active: ToolInteractionCoordinator.ActivePresentation
    ) -> some View {
        ToolInteractionPresentationSheet(
            active: active,
            coordinator: detailViewModel.toolInteractionCoordinator,
            memberContextStore: homeViewModel.memberContextStoreForBinding,
            stateStore: stateStore,
            listViewModel: listViewModel,
            detailViewModel: detailViewModel,
            knowledgeDependencies: knowledgeDependencies,
            knowledgeViewModel: knowledgeViewModel,
            taskManager: taskManager,
            homeViewModel: homeViewModel,
            toolPreviewRenderContext: detailViewModel.toolPreviewRenderContext,
            aiSettingsViewModel: aiSettingsViewModel,
            initialCompleteData: homeViewModel.dashboard?.medical.completeData,
            memberCompleteDataFetcher: detailViewModel,
            guideHomeDestinationBuilder: guideHomeDestinationBuilder,
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
            },
            onConversationThreadSelected: { selectedThreadID in
                switchThreadFromConversationList(to: selectedThreadID)
            }
        )
        .interactiveDismissDisabled(active.snapshot.requiresForcedSheetDismiss)
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
        // CHAT-000057 34.4：unknown 确认期间禁止发送（输入区已禁用，此处为兜底门禁）。
        guard isComposerBlockedByUnknownConfirmation == false else { return }
        // CHAT-000055 Q27/Q28：医院会话发送前必须过能力门禁。
        // 禁发时只提示、不发送；绝不自动重发、绝不改走普通 AI 链路。
        if case .hospital(let scope) = hospitalScopeResolution {
            // CHAT-000056 Q7.4：会话绑定成员已不是当前就诊人时禁止继续发送，
            // 患者需切回该成员或从当前成员重新进入医生卡发起咨询。
            guard scope.memberID == homeViewModel.memberContextStoreForBinding.context.selectedMemberID else {
                hospitalSendBlockedMessage = L10n.text(
                    "chat.hospital.send_member_mismatch",
                    fallback: "当前就诊人已切换，请切回原就诊人后再继续咨询"
                )
                return
            }
            // CHAT-000058 C-013/C-014：后台校验失败 → 立即停止后续发送（不中断进行中请求，不改投普通 AI）。
            // 线上问诊不依赖医生智能体运行配置，不因 AI runtime 失败禁发。
            if isTelemedicineConversation == false,
               detailViewModel.hospitalRuntimeUnavailableThreadIDs.contains(currentThreadID) {
                hospitalSendBlockedMessage = L10n.text(
                    "chat.hospital.runtime_unavailable",
                    fallback: "当前服务已不可用"
                )
                return
            }
            // CHAT-000058 C-003：专用配置未就绪时不发送，先补装载。线上问诊跳过。
            if isTelemedicineConversation == false,
               detailViewModel.hospitalComposerModelRows[currentThreadID] == nil {
                hospitalSendBlockedMessage = L10n.text(
                    "chat.hospital.runtime_preparing",
                    fallback: "医生智能体服务尚未就绪，请稍候重试"
                )
                if let accountID = listViewModel.signedInAccountID {
                    let threadID = currentThreadID
                    Task {
                        await detailViewModel.prepareHospitalRuntimeSession(
                            threadID: threadID,
                            scope: scope,
                            accountID: accountID
                        )
                    }
                }
                return
            }
            if let capabilities = hospitalCapabilities {
                guard capabilities.canSendMessage else {
                    hospitalSendBlockedMessage = hospitalReadOnlyMessage(for: capabilities.readOnlyReason)
                    return
                }
            } else {
                // context 未回源：先回源再判定，本次不直接发送。
                let threadID = currentThreadID
                Task {
                    await refreshHospitalConversationContext(threadID: threadID, scope: scope)
                    guard currentThreadID == threadID else { return }
                    if let capabilities = hospitalCapabilities {
                        if capabilities.canSendMessage {
                            sendCurrentDraftIfChatModelAvailable()
                        } else {
                            hospitalSendBlockedMessage = hospitalReadOnlyMessage(for: capabilities.readOnlyReason)
                        }
                    } else {
                        hospitalSendBlockedMessage = L10n.text(
                            "chat.hospital.send_unavailable",
                            fallback: "无法确认院内会话状态，请检查网络后重试"
                        )
                    }
                }
                return
            }
        }
        // 医生接管中 / 线上问诊：允许发送但 AI 不回复。
        let suppressAIReply = isDoctorTakeoverActive || isTelemedicineConversation
        if suppressAIReply == false {
            // CHAT-000058：医院会话可用性以单项锁定目录为准（上文已校验），普通会话仍以通用目录为准。
            if case .hospital = hospitalScopeResolution {
                guard detailViewModel.hospitalModelRow(for: currentThreadID) != nil else { return }
            } else {
                guard detailViewModel.chatScenarioModels.isEmpty == false else {
                    showNoAvailableChatModelAlert = true
                    return
                }
            }
        }
        detailViewModel.startSendingCurrentDraft(
            sendsOriginalImagesToAI: sendsOriginalImagesToAITemporarily,
            suppressAIReply: suppressAIReply
        )
    }

    /// CHAT-000055：只读原因 → 用户可读文案。
    private func hospitalReadOnlyMessage(for reason: String?) -> String {
        switch reason {
        case "agent_unpublished":
            return L10n.text("chat.hospital.readonly.agent_unpublished", fallback: "该医生智能体已下架，历史对话可查看，无法继续提问")
        case "member_access_revoked":
            return L10n.text("chat.hospital.readonly.member_revoked", fallback: "就诊人权限已变更，无法继续提问")
        default:
            return L10n.text("chat.hospital.readonly.generic", fallback: "当前会话为只读状态，无法继续提问")
        }
    }

    /// CHAT-000058 C-013/C-014：后台校验失败后固定展示“当前服务已不可用”。
    private var hospitalRuntimeUnavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.text("chat.hospital.runtime_unavailable", fallback: "当前服务已不可用"))
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
    }

    /// CHAT-000055：只读横幅（输入区上方固定展示）。
    @ViewBuilder
    private func hospitalReadOnlyBanner(reason: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(hospitalReadOnlyMessage(for: reason))
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
    }

    /// 线上问诊待医生查看：一对一会话，不套用「医生接管中」。
    private var telemedicineWaitingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "stethoscope")
                .foregroundStyle(Color.accentColor)
            Text(L10n.text("chat.hospital.telemedicine.waiting.banner", fallback: "问诊已提交，医生将尽快查看并回复"))
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.10))
    }

    /// CHAT-000057 38.6：医生接管中提示横幅（可发送，AI 不回复；与只读横幅互斥）。
    private var doctorTakeoverBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "stethoscope")
                .foregroundStyle(Color.accentColor)
            Text(L10n.text("chat.hospital.takeover.banner", fallback: "医生已接管，消息将由医生本人回复"))
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.10))
    }

    /// CHAT-000057 34.6/34.4：unknown 会话顶部受控横幅。
    /// 历史仅以只读呈现；重试合并入账号级 single-flight，失败继续只读、不弹打断式错误框。
    @ViewBuilder
    private func unifiedUnknownBanner(state: ConversationClassificationState) -> some View {
        HStack(spacing: 8) {
            switch state {
            case .resolving:
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text("chat.unified.confirming", fallback: "正在确认会话信息…"))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            case .retryableFailure:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.text("chat.unified.confirm_failed", fallback: "暂无法确认会话信息，历史消息仅供查看"))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Button(L10n.text("chat.unified.confirm_retry", fallback: "重试")) {
                    listViewModel.retryUnknownConfirmation(threadID: currentThreadID)
                }
                .font(.footnote.weight(.semibold))
            default:
                // conflict 等受控错误态：只读展示，不提供重试（重试无法解决绑定冲突）。
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.text("chat.unified.confirm_unavailable", fallback: "会话信息异常，历史消息仅供查看"))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
    }

    /// CHAT-000057 D-016/26.6：消息加载成功且身份确认后提交统一已读。
    /// unknown/conflict 与医院身份未确认（undetermined/failed）不提交；幂等可重复调用。
    private func markCurrentConversationReadIfAllowed(
        threadID: UUID,
        scopeResolution: HospitalScopeResolution
    ) async {
        guard currentThreadID == threadID else { return }
        let capability: ConversationCapability
        if listViewModel.isUnifiedMessageListEnabled,
           let item = listViewModel.unifiedItems.first(where: { $0.threadID == threadID }) {
            // 统一投影能力为唯一事实源（含 unknown.canMarkRead == false、撤权剔除）。
            capability = item.capability
        } else {
            switch scopeResolution {
            case .ordinary:
                capability = .ordinaryAI
            case .hospital(let scope):
                if hospitalCapabilities?.canSendMessage == false {
                    capability = .medicalReadOnly
                } else if scope.consultationID != nil {
                    capability = .telemedicineActive
                } else {
                    capability = .hospitalAgentActive
                }
            case .undetermined, .failed:
                // 26.3：医院 scope/context 未确认完成时不得当作普通会话提前清未读。
                return
            }
        }
        await listViewModel.markConversationRead(threadID: threadID, capability: capability)
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

        // CHAT-000054：点击“＋”前必须完成医院身份判定；判定失败阻断继承新建并展示错误。
        var resolution = hospitalScopeResolution
        if resolution == .undetermined {
            resolution = await resolveHospitalScope(for: oldThreadID)
            hospitalScopeResolution = resolution
        }
        switch resolution {
        case .hospital(let scope):
            guard let newHospitalThreadID = await createHospitalThreadInsideCurrentChatIfNeeded(
                scope: scope,
                from: oldThreadID
            ) else {
                if detailThreadCreationError == nil {
                    detailThreadCreationError = L10n.text("chat.thread.create_failed", fallback: "新建对话失败，请稍后再试")
                }
                logger.warning(
                    "chat.detail.new_thread_button.create_failed current=\(String(oldThreadID.uuidString.prefix(8))) hospital=1",
                    module: .general
                )
                return
            }
            logger.info(
                "chat.detail.new_thread_button.create_success old=\(String(oldThreadID.uuidString.prefix(8))) new=\(String(newHospitalThreadID.uuidString.prefix(8))) hospital=1",
                module: .general
            )
            switchDetailThread(from: oldThreadID, to: newHospitalThreadID)
            return
        case .failed:
            detailThreadCreationError = "无法确认院内会话身份，请检查网络后重试"
            return
        case .ordinary, .undetermined:
            break
        }

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

    /// CHAT-000054：仅普通会话展示“对话列表”入口；
    /// 医院会话与身份未明/判定失败时隐藏，避免跨入口泄露医院 Thread。
    private var showsOrdinaryConversationListButton: Bool {
        if case .ordinary = hospitalScopeResolution {
            return true
        }
        return false
    }

    /// CHAT-000054：身份判定失败后的手动重试（alert 内“重试”按钮触发）。
    @MainActor
    private func retryHospitalScopeResolution() async {
        let id = currentThreadID
        let resolution = await resolveHospitalScope(for: id)
        guard currentThreadID == id else { return }
        hospitalScopeResolution = resolution
        showHospitalScopeResolutionFailure = (resolution == .failed)
    }

    /// CHAT-000054：解析 thread 的医院会话身份。
    /// 顺序：本地 scope → 本地新建标记（普通会话快速路径）→ 服务端 context 回源。
    /// 服务端请求失败返回 `.failed`，由调用方阻断继承新建，不静默降级。
    @MainActor
    private func resolveHospitalScope(for threadID: UUID) async -> HospitalScopeResolution {
        guard let hospitalCare, let accountID = listViewModel.signedInAccountID else {
            return .ordinary
        }
        if let scope = hospitalCare.scopeStore.scope(for: threadID, accountID: accountID) {
            return .hospital(scope)
        }
        // 本地刚新建的普通会话不可能有医院绑定，跳过服务端往返。
        if stateStore.isThreadMarkedAsNewlyCreated(threadID) {
            return .ordinary
        }
        do {
            if let scope = try await hospitalCare.resolveScope.execute(threadID: threadID, accountID: accountID) {
                return .hospital(scope)
            }
            return .ordinary
        } catch {
            if error is CancellationError {
                return .undetermined
            }
            logger.warning(
                "chat.detail.hospital_scope.resolve_failed thread=\(String(threadID.uuidString.prefix(8))) error=\(error.localizedDescription)",
                module: .general
            )
            return .failed
        }
    }

    /// CHAT-000055：回源医院会话 context（能力 + 知识 Manifest），驱动发送门禁与知识同步。
    /// Q27/Q28：只读/禁发状态只能由该回源结果驱动；请求失败保持旧值，绝不本地猜测。
    @MainActor
    private func refreshHospitalConversationContext(threadID: UUID, scope: HospitalConversationScope) async {
        guard let hospitalCare, let accountID = listViewModel.signedInAccountID else { return }
        do {
            // Q28：携带 scope 中的 memberID 让服务端一并校验成员归属（撤权 → 禁发能力）。
            guard let result = try await hospitalCare.fetchContext.execute(
                threadID: threadID,
                memberID: scope.memberID
            ) else {
                // 404：服务端已无该医院会话绑定；保留本地能力，不主动降级当前页面。
                return
            }
            // 切换 thread 后迟到的回包不得覆盖新会话状态。
            guard currentThreadID == threadID else { return }
            hospitalCapabilities = result.capabilities
            hospitalKnowledgeManifest = result.manifest
            // CHAT-000057 38.6：服务端实时服务状态（doctor_joined → 医生接管，AI 不回复）。
            hospitalServiceStatus = result.serviceStatus.map { ConversationServiceStatus(rawValue: $0) }
            // 知识同步：capabilities.canSyncKnowledge == false（下架）时 reconcile 内部直接返回。
            await hospitalCare.knowledgeSync.reconcileWithManifest(
                result.manifest,
                agentID: scope.agentID,
                capabilities: result.capabilities,
                accountID: accountID
            )
        } catch {
            if error is CancellationError { return }
            logger.warning(
                "chat.detail.hospital_context.refresh_failed thread=\(String(threadID.uuidString.prefix(8))) error=\(error.localizedDescription)",
                module: .general
            )
        }
    }

    /// 医院会话内「新建对话」继承同一智能体，使用当前选中就诊人创建新线程。
    @MainActor
    private func createHospitalThreadInsideCurrentChatIfNeeded(
        scope: HospitalConversationScope,
        from oldThreadID: UUID
    ) async -> UUID? {
        guard let hospitalCare, let accountID = listViewModel.signedInAccountID else { return nil }
        guard let memberID = listViewModel.memberContextStore.context.selectedMemberID else {
            detailThreadCreationError = "请先选择就诊人"
            return nil
        }
        do {
            return try await hospitalCare.resolveOrCreate.execute(
                agentID: scope.agentID,
                memberID: memberID,
                hospitalID: scope.hospitalID,
                accountID: accountID,
                recentThreadID: nil
            )
        } catch {
            detailThreadCreationError = error.localizedDescription
            logger.warning(
                "chat.detail.new_thread_button.hospital_create_failed current=\(String(oldThreadID.uuidString.prefix(8))) error=\(error.localizedDescription)",
                module: .general
            )
            return nil
        }
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
        // CHAT-000054：切换 thread 后重置医院身份判定，由 .task(id:) 重新解析。
        hospitalScopeResolution = .undetermined
        showHospitalScopeResolutionFailure = false
        // CHAT-000055：能力与 Manifest 一并重置，避免旧会话门禁串到新会话。
        hospitalCapabilities = nil
        hospitalServiceStatus = nil
        hospitalKnowledgeManifest = nil
        // 恢复新 thread 的卡片动作快照（forceReload 清掉旧 thread 遗留 UI 状态）
        restoreCardActionSnapshotIfNeeded(forceReload: true)
    }
    
    /// Sheet 会话列表选择结果：复用当前 ChatView 原地切换，随后关闭列表。
    @MainActor
    private func switchThreadFromConversationList(to newThreadID: UUID) {
        let oldThreadID = currentThreadID
        if oldThreadID != newThreadID {
            switchDetailThread(from: oldThreadID, to: newThreadID)
        }
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
        
        let iso: (Date) -> String = { ChatCodableDateCodec.encodeISO8601Microseconds($0) }
        let sortedMessages = messages.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            if lhs.role != rhs.role { return Self.roleSortOrder(lhs.role) < Self.roleSortOrder(rhs.role) }
            return lhs.clientMessageID.uuidString < rhs.clientMessageID.uuidString
        }
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
                "created_at": iso(message.createdAt),
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
            "debug_time": iso(Date()),
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
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(ChatCodableDateCodec.encodeISO8601Microseconds(date))
        }
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// 相同时间戳时的角色兜底排序：system < user < assistant（与 Web 侧消息显示顺序一致）。
    private static func roleSortOrder(_ role: ChatMessageRole) -> Int {
        switch role {
        case .system: return 0
        case .user: return 1
        case .assistant: return 2
        }
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
        .onDisappear {
            // CHAT-000056 Q6：退出详情（含被子页面覆盖）清理仅用于 UI 的临时计数；
            // 返回后由下一帧 diff 重新累加。
            stateStore.clearUnseenRemoteMessageCount(for: threadID)
        }
    }
}
