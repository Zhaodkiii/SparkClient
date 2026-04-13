import Foundation

protocol ChatRepository: Sendable {
    func loadActiveThread() async -> ChatThread?
    func loadThread(id: UUID) async -> ChatThread?
    func loadThreads() async -> [ChatThread]
    func createThread(memberID: Int?, title: String) async -> ChatThread
    func setActiveThread(id: UUID) async
    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage]
    func countMessages(threadID: UUID) async -> Int
    func latestServerActivity(for threadID: UUID) async -> Date?
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
    ) async throws -> ChatMessage
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async
    func upsertRemoteThreads(_ threads: [ChatThread]) async
    func loadOutboxMessages(limit: Int) async -> [ChatMessage]
    func softDeleteThread(id: UUID) async
    func loadPendingThreadDeletionIDs(limit: Int) async -> [UUID]
    func removePendingThreadDeletionIDs(_ ids: [UUID]) async
    func deleteThread(id: UUID) async
    func loadSyncCursor() async -> ChatSyncCursor?
    func saveSyncCursor(_ cursor: ChatSyncCursor) async
    func loadThreadSyncCursor() async -> ChatSyncCursor?
    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async
    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor?
    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async
}
