import Combine
import Foundation

@MainActor
final class ChatDetailViewModel: ObservableObject {
    private let stateStore: ChatStateStore
    private let patientContextStore: PatientContextStore
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let retryFailedMessageUseCase: RetryFailedMessageUseCase
    private let syncChatUseCase: SyncChatUseCase
    private let notificationClient: any NotificationClient

    init(
        stateStore: ChatStateStore,
        patientContextStore: PatientContextStore,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        syncChatUseCase: SyncChatUseCase,
        notificationClient: any NotificationClient
    ) {
        self.stateStore = stateStore
        self.patientContextStore = patientContextStore
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.syncChatUseCase = syncChatUseCase
        self.notificationClient = notificationClient
    }

    func loadMessagesIfNeeded(for threadID: UUID) async {
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
        stateStore.setMessages(messages, for: threadID)
    }

    func sendCurrentDraft() async {
        guard stateStore.isSending == false else { return }
        guard let threadID = stateStore.selectedThreadID else { return }

        let draft = stateStore.draft(for: threadID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isEmpty == false else { return }

        stateStore.setSending(true)
        defer { stateStore.setSending(false) }

        do {
            let snapshot = try await sendMessageUseCase.execute(
                threadID: threadID,
                patientID: patientContextStore.context.selectedMemberID,
                userInput: draft
            )
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.clearDraft(for: threadID)
            stateStore.setError(nil)
        } catch {
            stateStore.setError(error.localizedDescription)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.send")
        }
    }

    func retryFailedMessage(clientMessageID: UUID) async {
        do {
            try await retryFailedMessageUseCase.execute(clientMessageID: clientMessageID)
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
        } catch {
            stateStore.setError(error.localizedDescription)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    func sync() async {
        do {
            try await syncChatUseCase.execute()
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
        } catch {
            stateStore.setError(error.localizedDescription)
        }
    }
}
