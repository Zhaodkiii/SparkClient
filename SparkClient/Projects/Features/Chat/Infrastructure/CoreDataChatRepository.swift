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

    func loadThreadListItems() async -> [ChatThreadListItem] {
        await store.loadThreadListItems()
    }

    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? {
        await store.loadThreadListItem(threadID: threadID)
    }

    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        await store.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: imageDeliveryModeRaw,
            rolePrompt: rolePrompt
        )
    }

    func setActiveThread(id: UUID) async {
        await store.setActiveThread(id: id)
    }

    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async {
        await store.updateThreadMemberBinding(threadID: threadID, memberID: memberID)
    }

    func loadMessages(threadID: UUID, limit: Int? = nil, before: Date? = nil) async -> [ChatMessage] {
        await store.loadMessages(threadID: threadID, limit: limit, before: before)
    }

    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] {
        await store.loadMessages(clientMessageIDs: clientMessageIDs)
    }

    func countMessages(threadID: UUID) async -> Int {
        await store.countMessages(threadID: threadID)
    }

    func latestServerActivity(for threadID: UUID) async -> Date? {
        await store.latestServerActivity(for: threadID)
    }

    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage {
        try await store.appendMessage(message)
    }

    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage {
        try await store.upsertLocalMessage(message)
    }

    func softDeleteMessage(clientMessageID: UUID) async {
        await store.softDeleteMessage(clientMessageID: clientMessageID)
    }

    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        await store.updateMessageDeliveryState(clientMessageID: clientMessageID, state: state)
    }

    func updateMessageBlocks(
        clientMessageID: UUID,
        blocks: [ChatMessageBlock],
        markPendingForSync: Bool
    ) async {
        await store.updateMessageBlocks(
            clientMessageID: clientMessageID,
            blocks: blocks,
            markPendingForSync: markPendingForSync
        )
    }

    @discardableResult
    func upsertMessageBlock(
        clientMessageID: UUID,
        block: ChatMessageBlock,
        markPendingForSync: Bool
    ) async -> Bool {
        await store.upsertMessageBlock(
            clientMessageID: clientMessageID,
            block: block,
            markPendingForSync: markPendingForSync
        )
    }

    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async {
        await store.upsertRemoteMessages(messages, in: threadID, enqueueAttachmentDownloadJobs: enqueueAttachmentDownloadJobs)
    }

    func upsertRemoteThreads(_ threads: [ChatThread]) async {
        await store.upsertRemoteThreads(threads)
    }

    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async {
        await store.updateThreadImageDeliveryMode(threadID: threadID, imageDeliveryModeRaw: imageDeliveryModeRaw)
    }

    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async {
        await store.updateThreadCurrentModelName(threadID: threadID, currentModelName: currentModelName)
    }

    func updateThreadGenerationConfig(
        threadID: UUID,
        currentModelName: String?,
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        maxMessages: Int,
        rolePrompt: String
    ) async {
        await store.updateThreadGenerationConfig(
            threadID: threadID,
            currentModelName: currentModelName,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            maxMessages: maxMessages,
            rolePrompt: rolePrompt
        )
    }

    func loadOutboxMessages(limit: Int) async -> [ChatMessage] {
        await store.loadOutboxMessages(limit: limit)
    }

    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock] {
        await store.loadPendingMessageBlocks(limit: limit)
    }

    func markMessageBlocksSynced(ids: [UUID]) async {
        await store.markMessageBlocksSynced(ids: ids)
    }


    func applyPushMessageAck(
        clientMessageID: UUID,
        serverMessageID: String?,
        serverUpdatedAt: Date
    ) async {
        await store.applyPushMessageAck(
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            serverUpdatedAt: serverUpdatedAt
        )
    }

    func softDeleteThread(id: UUID) async {
        await store.softDeleteThread(id: id)
    }

    func loadPendingThreadDeletionIDs(limit: Int = 50) async -> [UUID] {
        await store.loadPendingThreadDeletionIDs(limit: limit)
    }

    func removePendingThreadDeletionIDs(_ ids: [UUID]) async {
        await store.removePendingThreadDeletionIDs(ids)
    }

    func deleteThread(id: UUID) async {
        await store.softDeleteThread(id: id)
    }

    func loadSyncCursor() async -> ChatSyncCursor? {
        await store.loadSyncCursor()
    }

    func saveSyncCursor(_ cursor: ChatSyncCursor) async {
        await store.saveSyncCursor(cursor)
    }

    func loadThreadSyncCursor() async -> ChatSyncCursor? {
        await store.loadThreadSyncCursor()
    }

    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async {
        await store.saveThreadSyncCursor(cursor)
    }

    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor? {
        await store.loadMessageSyncCursor(for: threadID)
    }

    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async {
        await store.saveMessageSyncCursor(cursor, for: threadID)
    }

    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord] {
        await store.loadPendingAttachmentDownloadJobs(limit: limit)
    }

    func updateAttachmentDownloadJob(
        id: UUID,
        state: ChatAttachmentDownloadJobRecord.State,
        localFileURLString: String?
    ) async {
        await store.updateAttachmentDownloadJob(id: id, state: state, localFileURLString: localFileURLString)
    }
}
