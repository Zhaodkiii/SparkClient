import SwiftUI

struct ChatConversationListPage: View {
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var searchText = ""
    @State private var navigationSelection: UUID?
    @State private var hasLoaded = false

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
        .navigationTitle(L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search conversations")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await listViewModel.createThread()
                        guard let threadID = stateStore.selectedThreadID else { return }
                        await detailViewModel.loadMessagesIfNeeded(for: threadID)
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
            Text("No conversations yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Button {
                Task {
                    await listViewModel.createThread()
                    guard let threadID = stateStore.selectedThreadID else { return }
                    await detailViewModel.loadMessagesIfNeeded(for: threadID)
                    navigationSelection = threadID
                }
            } label: {
                Text("Create conversation")
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
            return "Yesterday"
        } else {
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}
