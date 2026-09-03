import Foundation

struct ChatPendingMessageBlock: Sendable {
    let threadID: UUID
    let clientMessageID: UUID
    let block: ChatMessageBlock
}

// MARK: - 拆分后的存储边界（对齐 Signal 式 store 分层；实现仍可为单一 `CoreDataChatRepository`）

protocol ChatThreadStoring: Sendable {
    func loadActiveThread() async -> ChatThread?
    func loadThread(id: UUID) async -> ChatThread?
    func loadThreads() async -> [ChatThread]
    /// 线程列表投影：每条线程仅聚合最新消息与未读数，避免对全量消息做 N 次加载。
    func loadThreadListItems() async -> [ChatThreadListItem]
    /// 单线程列表投影（用于 DB 通知后局部刷新一行）。
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem?
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread
    func setActiveThread(id: UUID) async
    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async
    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async
    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async
    func updateThreadTitle(threadID: UUID, title: String) async
    func updateThreadGenerationConfig(
        threadID: UUID,
        currentModelName: String?,
        temperature: Double?,
        topP: Double,
        maxTokens: Int?,
        maxMessages: Int,
        rolePrompt: String
    ) async
    func updateThreadAppearance(
        threadID: UUID,
        title: String,
        iconName: String?,
        iconColorName: String?
    ) async
    func updateThreadPinState(
        threadID: UUID,
        isPinned: Bool,
        pinnedAt: Date?
    ) async
    func softDeleteThread(id: UUID) async
    func loadPendingThreadDeletionIDs(limit: Int) async -> [UUID]
    func removePendingThreadDeletionIDs(_ ids: [UUID]) async
    func deleteThread(id: UUID) async
}

protocol ChatMessageStoring: Sendable {
    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage]
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage]
    func loadUsageSummary(clientMessageID: UUID) async -> ChatMessageUsageSummary?
    func countMessages(threadID: UUID) async -> Int
    func latestServerActivity(for threadID: UUID) async -> Date?
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage
    func softDeleteMessage(clientMessageID: UUID) async
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async
    func applyPushMessageAck(
        clientMessageID: UUID,
        serverMessageID: String?,
        serverUpdatedAt: Date,
        notifyUI: Bool
    ) async
    func updateMessageBlocks(clientMessageID: UUID, blocks: [ChatMessageBlock], markPendingForSync: Bool) async
    @discardableResult
    func upsertMessageBlock(clientMessageID: UUID, block: ChatMessageBlock, markPendingForSync: Bool) async -> Bool
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async
    func loadOutboxMessages(limit: Int) async -> [ChatMessage]
    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock]
    func markMessageBlocksSynced(ids: [UUID]) async
    func appendUsageEvent(_ event: ChatMessageUsageEvent) async
    func upsertUsageSummary(_ summary: ChatMessageUsageSummary) async
}

extension ChatMessageStoring {
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        await updateMessageDeliveryState(clientMessageID: clientMessageID, state: state, notifyUI: true)
    }

    func applyPushMessageAck(
        clientMessageID: UUID,
        serverMessageID: String?,
        serverUpdatedAt: Date
    ) async {
        await applyPushMessageAck(
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            serverUpdatedAt: serverUpdatedAt,
            notifyUI: true
        )
    }
}

protocol ChatSyncMetadataStoring: Sendable {
    func loadSyncCursor() async -> ChatSyncCursor?
    func saveSyncCursor(_ cursor: ChatSyncCursor) async
    func loadThreadSyncCursor() async -> ChatSyncCursor?
    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async
    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor?
    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async
    /// CHAT-000056 Q9：服务端明确 cursor 失效时，仅清除该 thread 的消息 cursor（不影响账号级与其他 thread）。
    func deleteMessageSyncCursor(for threadID: UUID) async
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
