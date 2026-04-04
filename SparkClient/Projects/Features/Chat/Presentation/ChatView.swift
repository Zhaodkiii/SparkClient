import SwiftUI

struct ChatView: View {
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            ConversationListView(
                items: stateStore.threadItems,
                selectedThreadID: stateStore.selectedThreadID,
                onSelect: { threadID in
                    listViewModel.selectThread(threadID)
                    Task { await detailViewModel.loadMessagesIfNeeded(for: threadID) }
                },
                onCreate: {
                    Task {
                        await listViewModel.createThread()
                        if let threadID = stateStore.selectedThreadID {
                            await detailViewModel.loadMessagesIfNeeded(for: threadID)
                        }
                    }
                },
                onDelete: { threadID in
                    Task {
                        await listViewModel.deleteThread(threadID)
                        if let selected = stateStore.selectedThreadID {
                            await detailViewModel.loadMessagesIfNeeded(for: selected)
                        }
                    }
                }
            )

            Divider()
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            await listViewModel.loadIfNeeded()
            if let threadID = stateStore.selectedThreadID {
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
            }
        }
        .onAppear {
            Task { await detailViewModel.chatPageDidAppear() }
        }
        .onDisappear {
            Task { await detailViewModel.chatPageDidDisappear() }
        }
        .refreshable {
            await detailViewModel.sync()
            await listViewModel.refreshThreads()
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
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: stateStore.selectedMessages.count) { _ in
                if let lastID = stateStore.selectedMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
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
        .padding(.horizontal, 16)
    }

    private func bubbleContent(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(
                L10n.text("chat.input.placeholder"),
                text: Binding(
                    get: { stateStore.draft(for: stateStore.selectedThreadID) },
                    set: { stateStore.setDraft($0, for: stateStore.selectedThreadID) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Button {
                Task { await detailViewModel.sendCurrentDraft() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(stateStore.draft(for: stateStore.selectedThreadID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stateStore.isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .topLeading) {
            Text("工具命令：/ocr <文件路径>  或  /confirm_draft")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .offset(y: -16)
        }
    }
}
