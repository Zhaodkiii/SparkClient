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

    @State private var hasLoaded = false
    @State private var conversationListLayoutNonce: UInt64 = 0
    @StateObject private var uiStateStore = ChatMessageUIStateStore()
    private let actionState = ChatMessageActionState()
    @State private var selectedTextSheet: ChatSelectableTextPayload?
    @StateObject private var speechHelper = ChatSpeechHelper()
    @State private var showCaptureFileImporter = false
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.signal.rawValue
    private let logger: Logger = ConsoleLogger()
    private static let cardActionSnapshotStorageKeyPrefix = "chat.view.card_action_snapshot."
    static let inlineErrorClientMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")!
    @State private var activeParameterCard: ParameterCardKind?
    @State private var overlaySettings = ChatThreadGenerationSettings(
        currentModelName: nil,
        temperature: 0.6,
        topP: 1.0,
        maxTokens: 4096,
        maxMessages: 20,
        rolePrompt: "",
        imageDeliveryMode: .directMultimodal
    )

    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(threadID.uuidString)|\(name)"
    }

    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .signal
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
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.startSendingCurrentDraft()
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
                }
            )
        case .hanlin:
            HanlinChatComposerView(
                threadID: threadID,
                modelReasoning: detailViewModel.reasoningToolbarContext,
                stateStore: stateStore,
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                boundMemberID: stateStore.selectedThread?.memberID,
                modelRows: detailViewModel.chatScenarioModels,
                onSend: {
                    KeyboardDismissHelper.dismissKeyboard()
                    detailViewModel.startSendingCurrentDraft()
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
                onSetMemberBinding: { memberID in
                    Task { await detailViewModel.updateThreadMemberBinding(memberID, for: threadID) }
                },
                onPersistSelectedChatModel: { modelName in
                    Task { await detailViewModel.updateThreadModel(modelName, for: threadID) }
                }
            )
        }

    }

    private var configuredLayout: some View {
        lifecycleLayout
    }

    private var navigationDecoratedLayout: some View {
        baseLayout
            .navigationTitle(stateStore.selectedThread?.listDisplayTitle ?? L10n.text("chat.title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerChrome
            }
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
                    } label: {
                        Label(L10n.text("chat.settings.menu"), systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                            Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                            Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                        }
                    } label: {
                        Label(L10n.text("chat.management.menu"), systemImage: "ellipsis.bubble")
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
            .sheet(item: $selectedTextSheet) { payload in
                CompatibleNavigationContainer(legacyStackStyle: true) {
                    ScrollView {
                        Text(payload.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(payload.title)
                }
            }
            .onAppear {
                Task { await detailViewModel.chatPageDidAppear() }
            }
            .onDisappear {
                Task { await detailViewModel.chatPageDidDisappear() }
            }
    }

    private var messageList: some View {
        ConversationMessageListRepresentable(
            threadID: threadID,
            stateStore: stateStore,
            detailViewModel: detailViewModel,
            uiStateStore: uiStateStore,
            speechHelper: speechHelper,
            taskManager: taskManager,
            logger: logger,
            actionState: actionState,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: stateStore.isBottomViewportLocked(for: threadID),
            streamingContentGeneration: stateStore.streamingContentGeneration,
            onLoadMore: {
                Task { await detailViewModel.loadMoreMessages(for: threadID) }
            },
            onRefresh: {
                await detailViewModel.sync()
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
                await listViewModel.refreshThreads()
                await MainActor.run {
                    conversationListLayoutNonce += 1
                }
            },
            onCaptureOpenFiles: {
                showCaptureFileImporter = true
            },
            conversationListLayoutNonce: conversationListLayoutNonce
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

    private var cardActionSnapshotStorageKey: String {
        Self.cardActionSnapshotStorageKeyPrefix + threadID.uuidString.lowercased()
    }

    private func restoreCardActionSnapshotIfNeeded(forceReload: Bool = false) {
        if forceReload {
            uiStateStore.applyCardActionSnapshot(.empty, forceReload: true)
        }
        guard let data = UserDefaults.standard.data(forKey: cardActionSnapshotStorageKey) else { return }
        guard let snapshot = try? JSONDecoder().decode(CardActionSnapshot.self, from: data) else { return }
        uiStateStore.applyCardActionSnapshot(snapshot, forceReload: false)
    }

    private func persistCardActionSnapshot() {
        let snapshot = uiStateStore.makeCardActionSnapshot()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
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
                    set: { updateOverlaySetting(temperature: $0) }
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
                    set: { updateOverlaySetting(maxTokens: $0) }
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
        }
    }

    private var temperatureOptions: [ChatThreadSettingOption<Double>] {
        stride(from: 0.1, through: 2.0, by: 0.1).map { raw in
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

    private var maxTokenOptions: [ChatThreadSettingOption<Int>] {
        [256, 512, 1024, 2048, 4096, 8192, 16384, 32768].map { value in
            ChatThreadSettingOption(
                id: "tokens-\(value)",
                value: value,
                title: "\(value)",
                detail: String(format: L10n.text("chat.settings.max_tokens.detail"), locale: Locale.current, value)
            )
        }
    }

    private var maxMessageOptions: [ChatThreadSettingOption<Int>] {
        [5, 10, 20, 30, 40, 50, 60].map { value in
            ChatThreadSettingOption(
                id: "messages-\(value)",
                value: value,
                title: "\(value)",
                detail: String(format: L10n.text("chat.settings.max_messages.detail"), locale: Locale.current, value)
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
}
