import SwiftUI

struct ChatConversationListPage: View {
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let pushAdapter: PushAdapter
    /// 引导卡片滑块 → 健康首页 destination（CHAT-000025）。
    /// 由 App 宿主注入；nil（旧宿主 / 未注入）时滑块降级为纯展示面板。
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    @State private var searchText = ""
    @State private var pendingThreadNavigation: UUID?
    @State private var hasLoaded = false
    @State private var hasHandledInitialAutoNavigation = false
    @State private var showNoAvailableChatModelAlert = false
    @State private var showAPIKeysSettingsSheet = false
    @State private var isEditingThreadAppearance = false
    @State private var editingThreadID: UUID?
    @State private var editingTitle: String = ""
    @State private var editingIconName: String? = nil
    @State private var editingIconColorName: String? = nil
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
            ToolbarItem(placement: .navigationBarLeading) {
                MainNavigationLink {
                    KnowledgeLibraryView(
                        dependencies: knowledgeDependencies,
                        viewModel: knowledgeViewModel
                    )
                } label: {
                    Image(systemName: "backpack.fill")
                }
                .accessibilityLabel(L10n.text("knowledge.library.title"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await createThreadIfAvailable()
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
            await handleInitialAutoNavigationIfNeeded()
        }
        .refreshable {
            await listViewModel.refreshThreads()
        }
        .alert(L10n.text("chat.list.no_available_model.title"), isPresented: $showNoAvailableChatModelAlert) {
            Button(L10n.text("chat.list.no_available_model.action")) {
                showAPIKeysSettingsSheet = true
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("chat.list.no_available_model.message"))
        }
        .sheet(isPresented: $showAPIKeysSettingsSheet) {
            NavigationView {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                showAPIKeysSettingsSheet = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $isEditingThreadAppearance) {
            ChatThreadAppearanceEditSheet(
                title: editingTitle,
                iconName: editingIconName,
                iconColorName: editingIconColorName,
                onSave: { title, iconName, iconColorName in
                    guard let id = editingThreadID else { return }
                    Task {
                        await listViewModel.updateThreadAppearance(
                            threadID: id,
                            title: title,
                            iconName: iconName,
                            iconColorName: iconColorName
                        )
                    }
                },
                onCancel: {}
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { pendingThreadNavigation != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingThreadNavigation = nil
                }
            }
        )) {
            if let threadID = pendingThreadNavigation {
                ChatView(
                    threadID: threadID,
                    stateStore: stateStore,
                    listViewModel: listViewModel,
                    detailViewModel: detailViewModel,
                    knowledgeDependencies: knowledgeDependencies,
                    knowledgeViewModel: knowledgeViewModel,
                    taskManager: taskManager,
                    homeViewModel: homeViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    guideHomeDestinationBuilder: guideHomeDestinationBuilder
                )
                .hidesMainTabBarWhenPushed()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if listViewModel.isRefreshingEmptyListFallback {
                ProgressView()
                Text(L10n.text("chat.list.empty.syncing"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "message.circle")
                    .font(.system(size: 52))
                    .foregroundColor(.secondary)
                Text(L10n.text("chat.list.empty.title"))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Button {
                    Task {
                        await createThreadIfAvailable()
                    }
                } label: {
                    Text(L10n.text("chat.list.empty.create"))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func threadRow(_ item: ChatThreadListItem) -> some View {
        MainNavigationLink {
            ChatView(
                threadID: item.id,
                stateStore: stateStore,
                listViewModel: listViewModel,
                detailViewModel: detailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder
            )
        } label: {
            HStack(alignment: .center, spacing: 10) {
                threadIcon(item.thread)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.thread.listDisplayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        if item.thread.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                beginEditingAppearance(for: item.thread)
            } label: {
                Label(L10n.text("chat.thread.edit", fallback: "编辑"), systemImage: "paintbrush")
            }

            Button {
                Task { await listViewModel.toggleThreadPinned(item.id) }
            } label: {
                Label(
                    item.thread.isPinned
                        ? L10n.text("chat.thread.unpin", fallback: "取消置顶")
                        : L10n.text("chat.thread.pin", fallback: "置顶"),
                    systemImage: item.thread.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive) {
                Task {
                    await listViewModel.deleteThread(item.id)
                }
            } label: {
                Label(L10n.text("common.delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task { await listViewModel.toggleThreadPinned(item.id) }
            } label: {
                Label(
                    item.thread.isPinned
                        ? L10n.text("chat.thread.unpin", fallback: "取消置顶")
                        : L10n.text("chat.thread.pin", fallback: "置顶"),
                    systemImage: item.thread.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(ChatThreadAppearanceResources.color(from: "hlBlue"))

            Button {
                beginEditingAppearance(for: item.thread)
            } label: {
                Label(L10n.text("chat.thread.edit", fallback: "编辑"), systemImage: "paintbrush")
            }
            .tint(ChatThreadAppearanceResources.color(from: "hlGreen"))
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

    @ViewBuilder
    private func threadIcon(_ thread: ChatThread) -> some View {
        let icon = (thread.iconName?.isEmpty == false ? thread.iconName : nil) ?? "bubble.left.circle"
        let colorName = (thread.iconColorName?.isEmpty == false ? thread.iconColorName : nil) ?? "accent"
        let tint = ChatThreadAppearanceResources.color(from: colorName)

        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 34, height: 34)
            .foregroundStyle(tint)
            .padding(6)
            .background(Circle().fill(.thinMaterial))
    }

    private func beginEditingAppearance(for thread: ChatThread) {
        editingThreadID = thread.id
        editingTitle = thread.title
        editingIconName = thread.iconName
        editingIconColorName = thread.iconColorName
        isEditingThreadAppearance = true
    }

    private func createThreadIfAvailable() async {
        guard await detailViewModel.hasAvailableChatModel() else {
            showNoAvailableChatModelAlert = true
            return
        }
        pushAdapter.requestAuthorizationIfNotDetermined()
        await listViewModel.createThread()
        guard let threadID = stateStore.selectedThreadID else { return }
        await navigateToThread(threadID)
    }

    private func handleInitialAutoNavigationIfNeeded() async {
        guard hasHandledInitialAutoNavigation == false else { return }
        hasHandledInitialAutoNavigation = true
        guard shouldSkipInitialAutoNavigation == false else { return }

        if let activeThreadID = mostRecentActiveThreadID(within: 5 * 60) {
            await navigateToThread(activeThreadID)
            return
        }

        await createThreadIfAvailable()
    }

    private func mostRecentActiveThreadID(within interval: TimeInterval) -> UUID? {
        let cutoff = Date().addingTimeInterval(-interval)
        return stateStore.threadItems.first(where: { $0.latestMessageAt >= cutoff })?.id
    }

    private var shouldSkipInitialAutoNavigation: Bool {
        guard let selectedThreadID = stateStore.selectedThreadID else { return false }
        let draft = stateStore.draft(for: selectedThreadID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty == false
    }

    private func navigateToThread(_ threadID: UUID) async {
        listViewModel.selectThread(threadID)
        await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
        pendingThreadNavigation = threadID
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
