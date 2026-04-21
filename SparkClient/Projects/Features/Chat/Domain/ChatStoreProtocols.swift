import Foundation

// MARK: - 拆分后的存储边界（对齐 Signal 式 store 分层；实现仍可为单一 `CoreDataChatRepository`）

protocol ChatThreadStoring: Sendable {
    func loadActiveThread() async -> ChatThread?
    func loadThread(id: UUID) async -> ChatThread?
    func loadThreads() async -> [ChatThread]
    /// 线程列表投影：每条线程仅聚合最新消息与未读数，避免对全量消息做 N 次加载。
    func loadThreadListItems() async -> [ChatThreadListItem]
    /// 单线程列表投影（用于 DB 通知后局部刷新一行）。
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem?
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?) async -> ChatThread
    func setActiveThread(id: UUID) async
    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async
    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async
    func updateThreadGenerationConfig(
        threadID: UUID,
        currentModelName: String?,
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        maxMessages: Int,
        rolePrompt: String
    ) async
    func softDeleteThread(id: UUID) async
    func loadPendingThreadDeletionIDs(limit: Int) async -> [UUID]
    func removePendingThreadDeletionIDs(_ ids: [UUID]) async
    func deleteThread(id: UUID) async
}

protocol ChatMessageStoring: Sendable {
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
    func updateMessageAttachments(
        clientMessageID: UUID,
        attachments: [ChatAttachment],
        markPendingForSync: Bool
    ) async
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async
    func loadOutboxMessages(limit: Int) async -> [ChatMessage]
}

protocol ChatSyncMetadataStoring: Sendable {
    func loadSyncCursor() async -> ChatSyncCursor?
    func saveSyncCursor(_ cursor: ChatSyncCursor) async
    func loadThreadSyncCursor() async -> ChatSyncCursor?
    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async
    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor?
    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async
}

protocol ChatRemoteThreadUpserting: Sendable {
    func upsertRemoteThreads(_ threads: [ChatThread]) async
}

protocol ChatAttachmentDownloadStoring: Sendable {
    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord]
    func updateAttachmentDownloadJob(
        id: UUID,
        state: ChatAttachmentDownloadJobRecord.State,
        localFileURLString: String?
    ) async
}

/// 聊天持久化门面：由 `CoreDataChatRepository` 等单一实现类满足全部子协议。
protocol ChatRepository: ChatThreadStoring,
    ChatMessageStoring,
    ChatRemoteThreadUpserting,
    ChatSyncMetadataStoring,
    ChatAttachmentDownloadStoring {}

extension ChatRepository {
    /// 默认不入队附件后台下载（出站合并等路径保持原语义）。
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async {
        await upsertRemoteMessages(messages, in: threadID, enqueueAttachmentDownloadJobs: false)
    }
}
