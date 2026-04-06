import Foundation

actor CoreDataChatRepository: ChatRepository {
    private let store: CoreDataChatStore

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.store = CoreDataChatStore(coreDataStack: coreDataStack, logger: logger)
    }

    func loadActiveThread() async -> ChatThread? {
        await store.loadActiveThread()
    }

    func loadThread(id: UUID) async -> ChatThread? {
        await store.loadThread(id: id)
    }

    func loadThreads() async -> [ChatThread] {
        await store.loadThreads()
    }

    func createThread(patientID: Int?, title: String) async -> ChatThread {
        await store.createThread(patientID: patientID, title: title)
    }

    func setActiveThread(id: UUID) async {
        await store.setActiveThread(id: id)
    }

    func loadMessages(threadID: UUID) async -> [ChatMessage] {
        await store.loadMessages(threadID: threadID)
    }

    func latestServerActivity(for threadID: UUID) async -> Date? {
        let messages = await store.loadMessages(threadID: threadID)
        return messages.map { $0.serverUpdatedAt ?? $0.createdAt }.max()
    }

    func appendMessage(
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        reasoningExpanded: Bool,
        reasoningVisibility: ChatReasoningVisibility,
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: ChatDeliveryState
    ) async throws -> ChatMessage {
        try await store.appendMessage(
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            reasoningExpanded: reasoningExpanded,
            reasoningVisibility: reasoningVisibility,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState
        )
    }

    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        await store.updateMessageDeliveryState(clientMessageID: clientMessageID, state: state)
    }

    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async {
        await store.upsertRemoteMessages(messages, in: threadID)
    }

    func loadOutboxMessages(limit: Int) async -> [ChatMessage] {
        await store.loadOutboxMessages(limit: limit)
    }

    func deleteThread(id: UUID) async {
        await store.deleteThread(id: id)
    }

    func loadSyncCursor() async -> ChatSyncCursor? {
        await store.loadSyncCursor()
    }

    func saveSyncCursor(_ cursor: ChatSyncCursor) async {
        await store.saveSyncCursor(cursor)
    }
}
