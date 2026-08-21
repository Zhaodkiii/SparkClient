import Combine
import Foundation

@MainActor
final class ChatListViewModel: ObservableObject {
    private let stateStore: ChatStateStore
    private let sessionStore: AppSessionStore
    private let memberContextStore: MemberContextStore
    private let loadMembersUseCase: LoadMembersUseCase
    private let selectMemberUseCase: SelectMemberUseCase
    private let selectedMemberIDPersistence: any SelectedMemberIDPersisting
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let createThreadUseCase: CreateThreadUseCase
    private let deleteThreadUseCase: DeleteThreadUseCase
    private let updateThreadMetadataUseCase: UpdateChatThreadMetadataUseCase
    private let chatSyncSupervisor: ChatSyncSupervisor
    private let notificationClient: any NotificationClient
    private let logger: Logger
    private var hasLoadedForList = false
    private var didAttemptEmptyListRemoteRefresh = false
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var hasFinishedInitialLocalLoad = false
    @Published private(set) var isRefreshingEmptyListFallback = false
    @Published private(set) var isCreatingQuickStartThread = false
    @Published private(set) var quickStartCreationError: String?

    init(
        stateStore: ChatStateStore,
        sessionStore: AppSessionStore,
        memberContextStore: MemberContextStore,
        loadMembersUseCase: LoadMembersUseCase,
        selectMemberUseCase: SelectMemberUseCase,
        selectedMemberIDPersistence: any SelectedMemberIDPersisting,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        createThreadUseCase: CreateThreadUseCase,
        deleteThreadUseCase: DeleteThreadUseCase,
        updateThreadMetadataUseCase: UpdateChatThreadMetadataUseCase,
        chatSyncSupervisor: ChatSyncSupervisor,
        notificationClient: any NotificationClient,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.sessionStore = sessionStore
        self.memberContextStore = memberContextStore
        self.loadMembersUseCase = loadMembersUseCase
        self.selectMemberUseCase = selectMemberUseCase
        self.selectedMemberIDPersistence = selectedMemberIDPersistence
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.createThreadUseCase = createThreadUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.updateThreadMetadataUseCase = updateThreadMetadataUseCase
        self.chatSyncSupervisor = chatSyncSupervisor
        self.notificationClient = notificationClient
        self.logger = logger

        NotificationCenter.default.publisher(for: .sparkChatDatabaseDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                Task { @MainActor in
                    guard case .signedIn = self.sessionStore.state else { return }
                    if let event = note.chatConversationChangeEvent {
                        guard event.affectsThreadList else { return }
                        if await self.tryPatchThreadList(for: event) {
                            return
                        }
                    }
                    await self.reloadThreads(selectFirstIfNeeded: false)
                }
            }
            .store(in: &cancellables)
    }

    func loadForListIfNeeded() async {
        guard hasLoadedForList == false else { return }
        hasLoadedForList = true
        await loadIfNeeded()
        hasFinishedInitialLocalLoad = true
        await refreshThreadsIfLocalEmpty(isSearching: false)
    }

    /// 本地列表首次加载完成且仍为空时，触发一次远端线程列表刷新（每页面生命周期最多一次）。
    func refreshThreadsIfLocalEmpty(isSearching: Bool) async {
        guard hasFinishedInitialLocalLoad else { return }
        guard isSearching == false else { return }
        guard didAttemptEmptyListRemoteRefresh == false else { return }
        guard isRefreshingEmptyListFallback == false else { return }
        guard stateStore.threadItems.isEmpty else { return }

        didAttemptEmptyListRemoteRefresh = true
        isRefreshingEmptyListFallback = true
        defer { isRefreshingEmptyListFallback = false }

        logger.info("会话列表本地为空，触发空结果兜底 refreshThreads", module: .general)
        await refreshThreads()
    }

    func loadIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        stateStore.setLoading(true)
        defer { stateStore.setLoading(false) }

        await ensureMemberContextLoaded()
        await reloadThreads(selectFirstIfNeeded: true)
    }

    func refreshThreads() async {
        do {
            try await chatSyncSupervisor.refreshThreadListIncremental()
        } catch {
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("common.error"),
                source: "chat.list.refresh"
            )
        }
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func createThread() async {
        let title = L10n.text("chat.default_thread_title")
        let thread = await createThreadUseCase.execute(
            memberID: memberContextStore.context.selectedMemberID,
            title: title
        )
        await reloadThreads(selectFirstIfNeeded: false)
        // CHAT-000028 3.3：新建对话标记，进入 ChatView 时以此触发生成（而非页面进入推断）
        stateStore.markThreadAsNewlyCreated(thread.id)
        stateStore.setSelectedThreadID(thread.id)
    }

    @discardableResult
    func createQuickStartThread(
        mode: ChatQuickStartMode,
        source: String
    ) async -> UUID? {
        logger.info(
            "Chat 快捷建会话开始 mode=\(mode.rawValue) source=\(source)",
            module: .general
        )
        isCreatingQuickStartThread = true
        quickStartCreationError = nil
        defer { isCreatingQuickStartThread = false }

        let thread = await createThreadUseCase.execute(
            memberID: memberContextStore.context.selectedMemberID,
            title: mode.title
        )
        await reloadThreads(selectFirstIfNeeded: false)
        // CHAT-000028 3.3：新建对话标记，进入 ChatView 时以此触发生成（而非页面进入推断）
        stateStore.markThreadAsNewlyCreated(thread.id)
        stateStore.setSelectedThreadID(thread.id)
        stateStore.setDraft(mode.initialDraft, for: thread.id)
        logger.info(
            "Chat 快捷建会话完成 thread=\(thread.id.uuidString.prefix(8)) source=\(source)",
            module: .general
        )
        return thread.id
    }

    func selectThread(_ threadID: UUID) {
        stateStore.setSelectedThreadID(threadID)
    }

    func selectAndPrepare(threadID: UUID) async {
        stateStore.setSelectedThreadID(threadID)
    }

    func search(text: String) -> [ChatThreadListItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return stateStore.threadItems }
        return stateStore.threadItems.filter { item in
            item.thread.listDisplayTitle.lowercased().contains(query)
            || item.latestMessagePreview.lowercased().contains(query)
        }
    }

    func deleteThread(_ threadID: UUID) async {
        await deleteThreadUseCase.execute(threadID: threadID)
        await reloadThreads(selectFirstIfNeeded: true)
    }

    func updateThreadAppearance(
        threadID: UUID,
        title: String,
        iconName: String?,
        iconColorName: String?
    ) async {
        await updateThreadMetadataUseCase.updateAppearance(
            threadID: threadID,
            title: title,
            iconName: iconName,
            iconColorName: iconColorName
        )
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func toggleThreadPinned(_ threadID: UUID) async {
        guard let item = stateStore.threadItems.first(where: { $0.id == threadID }) else { return }
        let now = Date()
        let isPinned = !item.thread.isPinned
        let pinnedAt: Date? = isPinned ? now : nil
        await updateThreadMetadataUseCase.updatePinState(
            threadID: threadID,
            isPinned: isPinned,
            pinnedAt: pinnedAt
        )
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func resetForSessionSwitch() {
        hasLoadedForList = false
        hasFinishedInitialLocalLoad = false
        didAttemptEmptyListRemoteRefresh = false
        isRefreshingEmptyListFallback = false
        isCreatingQuickStartThread = false
        quickStartCreationError = nil
    }

    private func reloadThreads(selectFirstIfNeeded: Bool) async {
        let threads = await loadChatThreadsUseCase.execute()
        stateStore.setThreads(threads)

        if selectFirstIfNeeded,
           stateStore.selectedThreadID == nil {
            stateStore.setSelectedThreadID(threads.first?.id)
        }
    }

    /// 已知 `threadID` 的变更：只刷新投影行，避免整表 `loadThreadListItems`。
    private func tryPatchThreadList(for event: ChatConversationChangeEvent) async -> Bool {
        guard let threadID = event.threadID else { return false }
        if stateStore.threadItems.isEmpty {
            return false
        }
        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            stateStore.upsertThreadListItem(item)
        } else {
            stateStore.removeThreadListItem(id: threadID)
        }
        return true
    }

    private func ensureMemberContextLoaded() async {
        if memberContextStore.context.members.isEmpty == false { return }
        guard case .signedIn(let session) = sessionStore.state else { return }
        let members = await loadMembersUseCase.execute()
        let persisted = selectedMemberIDPersistence.load(for: session.accountID)
        let preferred = memberContextStore.context.selectedMemberID ?? persisted
        let selectedID = selectMemberUseCase.execute(
            members: members,
            selectedID: preferred
        )
        memberContextStore.update(members: members, selectedMemberID: selectedID)
    }
}
