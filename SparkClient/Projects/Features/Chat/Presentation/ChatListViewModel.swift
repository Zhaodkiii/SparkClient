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
    private let chatSyncSupervisor: ChatSyncSupervisor
    private let notificationClient: any NotificationClient
    private var hasLoadedForList = false
    private var cancellables = Set<AnyCancellable>()

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
        chatSyncSupervisor: ChatSyncSupervisor,
        notificationClient: any NotificationClient
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
        self.chatSyncSupervisor = chatSyncSupervisor
        self.notificationClient = notificationClient

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
            memberID: nil,
            title: title
        )
        await reloadThreads(selectFirstIfNeeded: false)
        stateStore.setSelectedThreadID(thread.id)
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

    func resetForSessionSwitch() {
        hasLoadedForList = false
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
