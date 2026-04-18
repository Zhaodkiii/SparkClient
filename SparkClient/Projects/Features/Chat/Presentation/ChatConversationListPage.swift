import SwiftUI

struct ChatConversationListPage: View {
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var searchText = ""
    @State private var navigationSelection: UUID?
    @State private var hasLoaded = false
    /// 拖拽手势防抖标记：仅在一次拖拽开始时触发一次收键盘动作。
    @State private var hasDismissedKeyboardInCurrentDrag = false

    private var itemsToDisplay: [ChatThreadListItem] {
        listViewModel.search(text: searchText)
    }

    var body: some View {
        List {
            if itemsToDisplay.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(itemsToDisplay) { item in
                    threadRow(item)
                }
            }
        }
        .listStyle(.plain)
        // 对齐主流聊天列表交互：列表滚动时允许交互式收键盘。
        .chatScrollDismissesKeyboardInteractively()
        .navigationTitle(L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L10n.text("chat.list.search.placeholder"))
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    guard hasDismissedKeyboardInCurrentDrag == false else { return }
                    hasDismissedKeyboardInCurrentDrag = true
                    // 参考 Signal 的思路：在开始拖拽时主动让当前输入失焦。
                    KeyboardDismissHelper.dismissKeyboard()
                }
                .onEnded { _ in
                    hasDismissedKeyboardInCurrentDrag = false
                }
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await listViewModel.createThread()
                        guard let threadID = stateStore.selectedThreadID else { return }
                        await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
                        navigationSelection = threadID
                    }
                } label: {
                    Image(systemName: "plus.bubble")
                }
            }
        }
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            await listViewModel.loadForListIfNeeded()
        }
        .refreshable {
            await detailViewModel.sync()
            await listViewModel.refreshThreads()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message.circle")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(L10n.text("chat.list.empty.title"))
                .font(.headline)
                .foregroundColor(.secondary)
            Button {
                Task {
                    await listViewModel.createThread()
                    guard let threadID = stateStore.selectedThreadID else { return }
                    await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
                    navigationSelection = threadID
                }
            } label: {
                Text(L10n.text("chat.list.empty.create"))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func threadRow(_ item: ChatThreadListItem) -> some View {
        ZStack {
            NavigationLink(
                destination: ChatView(
                    threadID: item.id,
                    stateStore: stateStore,
                    listViewModel: listViewModel,
                    detailViewModel: detailViewModel
                ),
                tag: item.id,
                selection: $navigationSelection
            ) {
                EmptyView()
            }
            .hidden()

            Button {
                Task {
                    await listViewModel.selectAndPrepare(threadID: item.id)
                    navigationSelection = item.id
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    if let thumb = item.latestListImageAttachment {
                        ChatThreadListThumbnailView(attachment: thumb) { att in
                            try await detailViewModel.downloadChatAttachmentToLocalFile(attachment: att)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(item.thread.listDisplayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Text(formattedDate(item.latestMessageAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.latestMessagePreview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    Task {
                        await listViewModel.deleteThread(item.id)
                    }
                } label: {
                    Label(L10n.text("common.delete"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task {
                        await listViewModel.deleteThread(item.id)
                    }
                } label: {
                    Label(L10n.text("common.delete"), systemImage: "trash")
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return L10n.text("common.yesterday")
        } else {
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}
