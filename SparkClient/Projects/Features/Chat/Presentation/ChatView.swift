import SwiftUI

struct ChatView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var hasLoaded = false
    @State private var lastStreamingAutoScrollGeneration: UInt64 = 0
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.signal.rawValue

    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(threadID.uuidString)|\(name)"
    }

    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .signal
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            
            Group {
                switch composerStyle {
                case .signal:
                    ChatComposerView(
                        threadID: threadID,
                        stateStore: stateStore,
                        onSend: {
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                case .hanlin:
                    HanlinChatComposerView(
                        threadID: threadID,
                        modelReasoning: detailViewModel.reasoningToolbarContext,
                        stateStore: stateStore,
                        modelRows: detailViewModel.chatScenarioModels,
                        onSend: {
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                }
            }
        }
        .navigationTitle(stateStore.selectedThread?.listDisplayTitle ?? L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                        Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                        Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                    }
                } label: {
                    Label(L10n.text("chat.composer.style.title"), systemImage: "rectangle.split.2x1")
                }
            }
        }
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            listViewModel.selectThread(threadID)
            await detailViewModel.loadMessagesIfNeeded(for: threadID)
        }
        .task(id: threadID) {
            await detailViewModel.refreshChatModelPicker()
        }
        .task(id: reasoningRefreshId) {
            await detailViewModel.refreshReasoningToolbarContext(for: threadID)
        }
        .onAppear {
            Task { await detailViewModel.chatPageDidAppear() }
        }
        .onDisappear {
            Task { await detailViewModel.chatPageDidDisappear() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(stateStore.selectedMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if stateStore.isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 16)
            }
//            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: stateStore.selectedMessages.count) { _ in
                scrollToLastMessage(proxy: proxy, animated: true)
            }
            .onChange(of: stateStore.streamingContentGeneration) { generation in
                // 流式阶段降频滚动，避免每个 chunk 触发动画导致卡顿。
                let minGenerationStep: UInt64 = 4
                guard generation >= lastStreamingAutoScrollGeneration + minGenerationStep else { return }
                lastStreamingAutoScrollGeneration = generation
                scrollToLastMessage(proxy: proxy, animated: false)
            }
            .refreshable {
                await detailViewModel.sync()
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
                await listViewModel.refreshThreads()
            }
        }
    }

    private func scrollToLastMessage(proxy: ScrollViewProxy, animated: Bool) {
        if let lastID = stateStore.selectedMessages.last?.id {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubbleContent(message)
//                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleContent(message)
            }
        }
        .padding(.trailing, 16)
    }

    private func bubbleContent(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant,
               let reasoning = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               reasoning.isEmpty == false {
                ChatReasoningBlockView(text: reasoning)
            }

            Markdown(message.content)
                .markdownTheme(.chatBubble(foreground: message.role == .user ? .white : .primary))

            if message.deliveryState == .failed {
                Button {
                    Task {
                        await detailViewModel.retryFailedMessage(clientMessageID: message.clientMessageID)
                    }
                } label: {
                    Text(L10n.text("common.retry"))
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

}
