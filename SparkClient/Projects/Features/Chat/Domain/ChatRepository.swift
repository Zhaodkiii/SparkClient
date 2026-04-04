import Foundation

protocol ChatRepository: Sendable {
    func loadActiveThread() async -> ChatThread?
    func loadThread(id: UUID) async -> ChatThread?
    func loadThreads() async -> [ChatThread]
    func createThread(patientID: UUID?, title: String) async -> ChatThread
    func setActiveThread(id: UUID) async
    func loadMessages(threadID: UUID) async -> [ChatMessage]
    func appendMessage(
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: ChatDeliveryState
    ) async throws -> ChatMessage
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async
    func loadOutboxMessages(limit: Int) async -> [ChatMessage]
    func deleteThread(id: UUID) async
    func loadSyncCursor() async -> ChatSyncCursor?
    func saveSyncCursor(_ cursor: ChatSyncCursor) async
}
