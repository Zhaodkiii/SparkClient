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
    private let logger: Logger
    private var isRealtimeActive = false

    init(
        stateStore: ChatStateStore,
        patientContextStore: PatientContextStore,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        syncChatUseCase: SyncChatUseCase,
        notificationClient: any NotificationClient,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.patientContextStore = patientContextStore
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.syncChatUseCase = syncChatUseCase
        self.notificationClient = notificationClient
        self.logger = logger
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

        logger.info(
            "发送对话开始，thread=\(shortID(threadID)), patient=\(shortID(patientContextStore.context.selectedMemberID)), length=\(draft.count)",
            category: "chat_flow"
        )
        stateStore.setSending(true)
        defer { stateStore.setSending(false) }

        do {
            let streamingMessageID = UUID()
            let stateStore = self.stateStore
            stateStore.startStreamingAssistant(
                threadID: threadID,
                clientMessageID: streamingMessageID,
                kind: .text
            )
            let snapshot = try await sendMessageUseCase.execute(
                threadID: threadID,
                patientID: patientContextStore.context.selectedMemberID,
                userInput: draft,
                onAssistantPartial: { partial, kind in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(
                            threadID: threadID,
                            kind: kind,
                            content: partial
                        )
                    }
                }
            )
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.clearDraft(for: threadID)
            stateStore.setError(nil)
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                category: "chat_flow"
            )
        } catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(error.localizedDescription)
            logger.error("发送对话失败：\(error.localizedDescription)", category: "chat_flow")
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.send")
        }
    }

    func retryFailedMessage(clientMessageID: UUID) async {
        logger.info("重试失败消息开始，clientMessageID=\(shortID(clientMessageID))", category: "chat_flow")
        do {
            try await retryFailedMessageUseCase.execute(clientMessageID: clientMessageID)
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.info("重试失败消息完成，clientMessageID=\(shortID(clientMessageID))", category: "chat_flow")
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("重试失败消息失败：\(error.localizedDescription)", category: "chat_flow")
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    func sync() async {
        logger.debug("手动聊天同步开始", category: "chat_flow")
        do {
            try await syncChatUseCase.execute()
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.debug("手动聊天同步完成", category: "chat_flow")
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("手动聊天同步失败：\(error.localizedDescription)", category: "chat_flow")
        }
    }

    func chatPageDidAppear() async {
        guard isRealtimeActive == false else { return }
        isRealtimeActive = true
        await syncChatUseCase.startRealtime()
    }

    func chatPageDidDisappear() async {
        guard isRealtimeActive else { return }
        isRealtimeActive = false
        await syncChatUseCase.stopRealtime()
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }
}
