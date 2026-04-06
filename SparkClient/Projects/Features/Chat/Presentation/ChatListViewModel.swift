import Combine
import Foundation

@MainActor
final class ChatListViewModel: ObservableObject {
    private let stateStore: ChatStateStore
    private let sessionStore: AppSessionStore
    private let patientContextStore: PatientContextStore
    private let loadPatientsUseCase: LoadPatientsUseCase
    private let selectPatientUseCase: SelectPatientUseCase
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let createThreadUseCase: CreateThreadUseCase
    private let deleteThreadUseCase: DeleteThreadUseCase
    private let notificationClient: any NotificationClient
    private var hasLoadedForList = false

    init(
        stateStore: ChatStateStore,
        sessionStore: AppSessionStore,
        patientContextStore: PatientContextStore,
        loadPatientsUseCase: LoadPatientsUseCase,
        selectPatientUseCase: SelectPatientUseCase,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        createThreadUseCase: CreateThreadUseCase,
        deleteThreadUseCase: DeleteThreadUseCase,
        notificationClient: any NotificationClient
    ) {
        self.stateStore = stateStore
        self.sessionStore = sessionStore
        self.patientContextStore = patientContextStore
        self.loadPatientsUseCase = loadPatientsUseCase
        self.selectPatientUseCase = selectPatientUseCase
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.createThreadUseCase = createThreadUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.notificationClient = notificationClient
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

        await ensurePatientContextLoaded()
        await reloadThreads(selectFirstIfNeeded: true)
    }

    func refreshThreads() async {
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func createThread() async {
        let title = L10n.text("chat.default_thread_title")
        let thread = await createThreadUseCase.execute(
            patientID: patientContextStore.context.selectedMemberID,
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
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
        stateStore.setMessages(messages, for: threadID)
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

    private func reloadThreads(selectFirstIfNeeded: Bool) async {
        let threads = await loadChatThreadsUseCase.execute()
        stateStore.setThreads(threads)

        if selectFirstIfNeeded,
           stateStore.selectedThreadID == nil {
            stateStore.setSelectedThreadID(threads.first?.id)
        }
    }

    private func ensurePatientContextLoaded() async {
        if patientContextStore.context.members.isEmpty == false { return }
        let members = await loadPatientsUseCase.execute()
        let selectedID = selectPatientUseCase.execute(
            members: members,
            selectedID: patientContextStore.context.selectedMemberID
        )
        patientContextStore.update(members: members, selectedMemberID: selectedID)
    }
}
