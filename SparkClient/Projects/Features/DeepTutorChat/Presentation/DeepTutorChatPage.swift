import SwiftUI

struct DeepTutorChatPage: View {
    let conversationID: UUID
    @ObservedObject var viewModel: DeepTutorChatViewModel
    @StateObject private var refreshCoordinator: DeepTutorRefreshCoordinator
    @State private var isComposerFocused = false
    @State private var showAttachmentPreview = false
    @State private var previewInputs: [FilePreviewInput] = []
    @State private var previewStartIndex = 0

    init(conversationID: UUID, viewModel: DeepTutorChatViewModel) {
        self.conversationID = conversationID
        self.viewModel = viewModel
        _refreshCoordinator = StateObject(wrappedValue: DeepTutorRefreshCoordinator(conversationID: conversationID, viewModel: viewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            if viewModel.isQuizInlineInputFocused == false {
                DeepTutorComposerView(
                    text: Binding(
                        get: { viewModel.state.draftText },
                        set: { viewModel.updateDraft($0) }
                    ),
                    isFocused: $isComposerFocused,
                    capability: Binding(
                        get: { viewModel.state.activeCapability },
                        set: { viewModel.updateCapability($0) }
                    ),
                    selectedModelName: $viewModel.composerSelectedModelName,
                    modelRows: viewModel.chatScenarioModels,
                    modelDisplayTitle: viewModel.selectedModelDisplayTitle,
                    modelIconName: viewModel.selectedModelIconName,
                    isModelPickerDisabled: viewModel.state.isStreaming,
                    boundMemberDisplayModel: viewModel.boundMemberDisplayModel,
                    members: viewModel.availableMembers,
                    onPersistSelectedModel: { modelName in
                        Task { await viewModel.updateConversationModel(modelName, for: conversationID) }
                    },
                    hasMessages: viewModel.state.messages.isEmpty == false,
                    isStreaming: viewModel.state.isStreaming,
                    references: [],
                    attachmentDrafts: viewModel.composerAttachmentDrafts,
                    onAttachmentsPicked: { viewModel.handleAttachmentsPicked($0) },
                    onUploadAttachment: { viewModel.uploadComposerAttachment(id: $0) },
                    onRetryAttachmentUpload: { viewModel.retryComposerAttachmentUpload(id: $0) },
                    onRemoveAttachment: { viewModel.removeComposerAttachment(id: $0) },
                    onPreviewAttachment: { previewComposerAttachment(id: $0) },
                    onSetMemberBinding: { memberID in
                        Task { await viewModel.updateConversationMemberBinding(memberID, source: .composerManual) }
                    },
                    onSend: {
                        Task { await viewModel.sendMessage() }
                    },
                    onStop: {
                        viewModel.stopStreaming()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isQuizInlineInputFocused)
        .navigationTitle(viewModel.displayConversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await viewModel.logDebugInfo(
                            conversationID: conversationID,
                            pageContext: DeepTutorChatDebugPageContext(
                                keyboardFocused: isComposerFocused,
                                refreshCoordinatorLayoutNonce: refreshCoordinator.layoutNonce
                            )
                        )
                    }
                } label: {
                    Label(
                        L10n.text("chat.management.print_debug_info"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
        }
        .unifiedFilePreview(
            isPresented: $showAttachmentPreview,
            inputs: previewInputs,
            startIndex: previewStartIndex
        )
        .task(id: conversationID) {
            await viewModel.openConversation(conversationID)
        }
    }

    private func previewComposerAttachment(id: UUID) {
        let drafts = viewModel.composerAttachmentDrafts
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        previewInputs = DeepTutorAttachmentPreviewInputBuilder.previewInputs(for: drafts)
        previewStartIndex = index
        showAttachmentPreview = true
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loadingLocal:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .streaming, .resolvingAskUser, .resolvingMemberSelection:
            DeepTutorMessageListRepresentable(
                conversationID: conversationID,
                viewModel: viewModel,
                refreshCoordinator: refreshCoordinator,
                fileTransferService: viewModel.composerFileTransferService
            )
        case .error(let message):
            VStack(spacing: 12) {
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.openConversation(conversationID) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DeepTutorConversationListPage: View {
    @ObservedObject var viewModel: DeepTutorChatViewModel
    @State private var hasLoaded = false
    @State private var showsCreationError = false
    @State private var hasDismissedKeyboardInCurrentDrag = false

    var body: some View {
        List {
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.conversations) { item in
                    Button {
                        viewModel.selectedConversationID = item.id
                    } label: {
                        conversationRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .chatScrollDismissesKeyboardInteractively()
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    guard hasDismissedKeyboardInCurrentDrag == false else { return }
                    hasDismissedKeyboardInCurrentDrag = true
                    DeepTutorChatLog.keyboardDismiss(source: "conversation_list_drag")
                    KeyboardDismissHelper.dismissKeyboard()
                }
                .onEnded { _ in
                    hasDismissedKeyboardInCurrentDrag = false
                }
        )
        .navigationTitle("DeepTutor")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.createAndOpenConversation(source: "toolbar") }
                } label: {
                    if viewModel.isCreatingConversation {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.bubble")
                    }
                }
                .disabled(viewModel.isCreatingConversation)
            }
        }
        .navigationDestination(item: $viewModel.selectedConversationID) { conversationID in
            DeepTutorChatPage(conversationID: conversationID, viewModel: viewModel)
        }
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            await viewModel.loadConversationsIfNeeded()
        }
        .refreshable {
            await viewModel.refreshConversations()
        }
        .onChange(of: viewModel.selectedConversationID) { oldValue, newValue in
            if oldValue != nil, newValue == nil {
                Task { await viewModel.refreshConversations(source: "return") }
            }
        }
        .onChange(of: viewModel.conversationCreationError) { _, newValue in
            showsCreationError = newValue != nil
        }
        .alert("无法创建对话", isPresented: $showsCreationError) {
            Button("确定", role: .cancel) {
                viewModel.clearConversationCreationError()
            }
        } message: {
            Text(viewModel.conversationCreationError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("DeepTutor 对话")
                .font(.headline)
            Text("创建本地 DeepTutor 对话，体验与 Web 对齐的消息流。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.createAndOpenConversation(source: "empty_state") }
            } label: {
                if viewModel.isCreatingConversation {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("新建对话")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCreatingConversation)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    private func conversationRow(_ item: DeepTutorConversationListItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DeepTutorSessionTitle.displayTitle(item.conversation.title))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(formattedListDate(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(previewText(for: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let statusText = conversationStatusText(for: item) {
                HStack(spacing: 6) {
                    if item.latestMessageStatus == .streaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(item.latestMessageStatus == .failed ? .red : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func formattedListDate(_ item: DeepTutorConversationListItem) -> String {
        let date = item.latestMessageAt
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func conversationStatusText(for item: DeepTutorConversationListItem) -> String? {
        switch item.latestMessageStatus {
        case .streaming:
            return "正在回答"
        case .failed:
            return "失败可重试"
        default:
            return nil
        }
    }

    private func previewText(for item: DeepTutorConversationListItem) -> String {
        let preview = item.latestPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty || preview == "…" {
            return "暂无消息"
        }
        return preview
    }
}
