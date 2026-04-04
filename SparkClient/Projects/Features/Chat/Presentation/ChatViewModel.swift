import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var thread: ChatThread?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published var draftText: String = ""

    private let sessionStore: AppSessionStore
    private let patientContextStore: PatientContextStore
    private let loadPatientsUseCase: LoadPatientsUseCase
    private let selectPatientUseCase: SelectPatientUseCase
    private let loadThreadUseCase: LoadChatThreadUseCase
    private let createThreadUseCase: CreateChatThreadUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let notificationClient: any NotificationClient

    init(
        sessionStore: AppSessionStore,
        patientContextStore: PatientContextStore,
        loadPatientsUseCase: LoadPatientsUseCase,
        selectPatientUseCase: SelectPatientUseCase,
        loadThreadUseCase: LoadChatThreadUseCase,
        createThreadUseCase: CreateChatThreadUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        notificationClient: any NotificationClient
    ) {
        self.sessionStore = sessionStore
        self.patientContextStore = patientContextStore
        self.loadPatientsUseCase = loadPatientsUseCase
        self.selectPatientUseCase = selectPatientUseCase
        self.loadThreadUseCase = loadThreadUseCase
        self.createThreadUseCase = createThreadUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.notificationClient = notificationClient
    }

    func loadIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        await ensurePatientContextLoaded()

        if let snapshot = await loadThreadUseCase.execute() {
            apply(snapshot: snapshot)
            return
        }

        let snapshot = await createThreadUseCase.execute(title: L10n.text("chat.default_thread_title"))
        apply(snapshot: snapshot)
    }

    func sendCurrentDraft() async {
        guard isSending == false else { return }
        isSending = true
        defer { isSending = false }

        do {
            let snapshot = try await sendMessageUseCase.execute(
                threadID: thread?.id,
                patientID: patientContextStore.context.selectedMemberID,
                userInput: draftText
            )
            draftText = ""
            apply(snapshot: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.send")
        }
    }

    private func apply(snapshot: ChatThreadSnapshot) {
        thread = snapshot.thread
        messages = snapshot.messages
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
