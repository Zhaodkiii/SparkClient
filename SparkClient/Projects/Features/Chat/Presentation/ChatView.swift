import SwiftUI
import UIKit
import Combine

struct ChatView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var hasLoaded = false
    @State private var conversationListLayoutNonce: UInt64 = 0
    @StateObject private var uiStateStore = ChatMessageUIStateStore()
    private let actionState = ChatMessageActionState()
    @State private var selectedTextSheet: ChatSelectableTextPayload?
    @StateObject private var speechHelper = ChatSpeechHelper()
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.signal.rawValue
    @StateObject private var taskManager = TaskManager.shared
    private let logger: Logger = ConsoleLogger()
    private static let cardActionSnapshotStorageKeyPrefix = "chat.view.card_action_snapshot."

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
                    Task { await detailViewModel.sendCurrentDraft() }
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
                modelRows: detailViewModel.chatScenarioModels,
                onSend: {
                    KeyboardDismissHelper.dismissKeyboard()
                    Task { await detailViewModel.sendCurrentDraft() }
                },
                onAttachmentsPicked: { attachments in
                    detailViewModel.enqueueComposerAttachments(attachments, for: threadID)
                },
                onRemoveAttachment: { attachmentID in
                    detailViewModel.removeComposerAttachment(id: attachmentID, for: threadID)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                            Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                            Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                        }
                    } label: {
                        Label(L10n.text("chat.composer.style.title"), systemImage: "rectangle.split.2x1")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await detailViewModel.setThreadImageDeliveryMode(.directMultimodal, for: threadID)
                            }
                        } label: {
                            Label(L10n.text("chat.image_delivery.direct"), systemImage: "photo.on.rectangle")
                        }
                        .disabled(detailViewModel.currentModelSupportsMultimodal == false)
                        Button {
                            Task {
                                await detailViewModel.setThreadImageDeliveryMode(.localOCR, for: threadID)
                            }
                        } label: {
                            Label(L10n.text("chat.image_delivery.ocr_only"), systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label(L10n.text("chat.image_delivery.menu"), systemImage: "photo.on.rectangle.angled")
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
                NavigationView {
                    ScrollView {
                        Text(payload.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(payload.title)
                }
                .navigationViewStyle(.stack)
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
            conversationListLayoutNonce: conversationListLayoutNonce
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatScrollDismissesKeyboardInteractively()
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
}
