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
    private let createThreadUseCase: CreateThreadUseCase
    private let deleteThreadUseCase: DeleteThreadUseCase
    private let syncChatUseCase: SyncChatUseCase
    private let notificationClient: any NotificationClient

    init(
        stateStore: ChatStateStore,
        sessionStore: AppSessionStore,
        patientContextStore: PatientContextStore,
        loadPatientsUseCase: LoadPatientsUseCase,
        selectPatientUseCase: SelectPatientUseCase,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        createThreadUseCase: CreateThreadUseCase,
        deleteThreadUseCase: DeleteThreadUseCase,
        syncChatUseCase: SyncChatUseCase,
        notificationClient: any NotificationClient
    ) {
        self.stateStore = stateStore
        self.sessionStore = sessionStore
        self.patientContextStore = patientContextStore
        self.loadPatientsUseCase = loadPatientsUseCase
        self.selectPatientUseCase = selectPatientUseCase
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.createThreadUseCase = createThreadUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.syncChatUseCase = syncChatUseCase
        self.notificationClient = notificationClient
    }

    func loadIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        stateStore.setLoading(true)
        defer { stateStore.setLoading(false) }

        await ensurePatientContextLoaded()
        await reloadThreads(selectFirstIfNeeded: true)

        do {
            try await syncChatUseCase.execute()
            await reloadThreads(selectFirstIfNeeded: false)
        } catch {
            stateStore.setError(error.localizedDescription)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.sync")
        }
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
