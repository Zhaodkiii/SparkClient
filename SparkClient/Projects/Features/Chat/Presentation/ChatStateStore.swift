import Combine
import Foundation

/// 聊天 **UI 工作集**（选中线程、草稿、流式助手占位、分页标志等）。持久真相源为 ``ChatRepository`` / ``ChatQueryService``；
/// 持久化写入成功后广播 ``Notification/Name/sparkChatDatabaseDidChange``，由列表/详情 ViewModel 经 Query 层刷新。
@MainActor
final class ChatStateStore: ObservableObject {
    private struct MessagePaging: Sendable {
        var hasMore: Bool
        var isLoadingMore: Bool
    }

    private struct StreamingAssistant: Sendable {
        let threadID: UUID
        let clientMessageID: UUID
        var state: ChatStreamingAssistantState
        let createdAt: Date
    }
    private let streamingReducer = ChatStreamingAssistantReducer()

    @Published private(set) var threadItems: [ChatThreadListItem] = []
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var threadErrorMessages: [UUID: String] = [:]

    @Published private var composerDrafts: [UUID: ChatComposerDraft] = [:]
    /// 待发图片上传进度（发送过程中由 `SendChatMessageUseCase` 回写）。
    @Published private(set) var composerAttachmentUploadProgress: [UUID: Double] = [:]
    /// 选图后即上传/OCR 的附件状态（按附件 id 记录）。
    @Published private(set) var composerPreparedAttachmentStates: [UUID: ChatComposerPreparedAttachmentState] = [:]
    @Published private var streamingAssistants: [UUID: StreamingAssistant] = [:]
    @Published private var messagePagingByThread: [UUID: MessagePaging] = [:]
    @Published private var bottomViewportLockedThreadIDs: Set<UUID> = []
    /// Bumps on each streaming text/reasoning update so views can scroll even when message count is unchanged.
    @Published private(set) var streamingContentGeneration: UInt64 = 0
    /// Bumps when the conversation view should force-scroll to the newest message, such as after sending.
    @Published private(set) var scrollToBottomRequestGenerationByThread: [UUID: UInt64] = [:]

    var selectedThread: ChatThread? {
        threadItems.first(where: { $0.id == selectedThreadID })?.thread
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedThreadID else { return [] }
        return conversationListItems(for: selectedThreadID)
    }

    /// 仅 Core Data 中的消息（不含流式尾部占位）。
    func persistedMessages(for threadID: UUID) -> [ChatMessage] {
        messagesByThread[threadID] ?? []
    }

    /// 会话列表展示用：持久化消息 + 流式尾部（按 `clientMessageID` 合并，避免整表 identity 抖动）。
    func conversationListItems(for threadID: UUID) -> [ChatMessage] {
        let persisted = messagesByThread[threadID] ?? []
        let tail = streamingTailMessage(for: threadID)
        return ConversationRenderState.mergedList(persisted: persisted, streamingTail: tail)
    }

    private func streamingTailMessage(for threadID: UUID) -> ChatMessage? {
        guard let streaming = streamingAssistants[threadID] else { return nil }
        return ChatMessage(
            id: streaming.clientMessageID,
            threadID: streaming.threadID,
            role: .assistant,
            blocks: streaming.state.blocks,
            clientMessageID: streaming.clientMessageID,
            serverMessageID: nil,
            deliveryState: .sending,
            createdAt: streaming.createdAt,
            serverUpdatedAt: nil,
            isTombstone: false,
            modelName: selectedThread?.currentModelName
        )
    }

    /// 当前流式助手占位的消息快照。用于用户主动中断时，把已生成内容固化为正式消息。
    func activeStreamingAssistantMessage(for threadID: UUID) -> ChatMessage? {
        streamingTailMessage(for: threadID)
    }

    func isStreamingAssistantActive(for threadID: UUID) -> Bool {
        streamingAssistants[threadID] != nil
    }

    func setThreads(_ items: [ChatThreadListItem]) {
        threadItems = items
        if let selectedThreadID, items.contains(where: { $0.id == selectedThreadID }) == false {
            self.selectedThreadID = items.first?.id
        }
        if self.selectedThreadID == nil {
            self.selectedThreadID = items.first?.id
        }
    }

    /// 用投影行替换或插入一条，并按最新消息时间排序（用于 DB 通知局部刷新）。
    func upsertThreadListItem(_ item: ChatThreadListItem) {
        var next = threadItems.filter { $0.id != item.id }
        next.append(item)
        threadItems = next.sorted { $0.latestMessageAt > $1.latestMessageAt }
        if selectedThreadID == nil {
            selectedThreadID = threadItems.first?.id
        }
    }

    /// 线程已从列表移除（如软删）时更新内存列表与选中态。
    func removeThreadListItem(id: UUID) {
        threadItems.removeAll { $0.id == id }
        if selectedThreadID == id {
            selectedThreadID = threadItems.first?.id
        }
    }

    func setSelectedThreadID(_ threadID: UUID?) {
        selectedThreadID = threadID
    }

    /// - Parameter clearStreamingAssistant: Set `false` while a reply is streaming so mid-send reloads (e.g. after user message persist) do not wipe `streamingAssistants`.
    func setMessages(
        _ messages: [ChatMessage],
        for threadID: UUID,
        clearStreamingAssistant: Bool = true,
        hasMore: Bool? = nil
    ) {
        messagesByThread[threadID] = messages
        if clearStreamingAssistant {
            streamingAssistants[threadID] = nil
        }
        if let hasMore {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
        }
    }

    func prependMessages(_ messages: [ChatMessage], for threadID: UUID, hasMore: Bool) {
        guard messages.isEmpty == false else {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
            return
        }
        let current = messagesByThread[threadID] ?? []
        let existingIDs = Set(current.map(\.id))
        let mergedPrefix = messages.filter { existingIDs.contains($0.id) == false }
        messagesByThread[threadID] = mergedPrefix + current
        let paging = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: paging.isLoadingMore)
    }

    func updateMessageBlocksFromIncoming(
        threadID: UUID,
        clientMessageID: UUID,
        incomingBlocks: [ChatMessageBlock]
    ) {
        guard let messages = messagesByThread[threadID],
              let idx = messages.lastIndex(where: { $0.clientMessageID == clientMessageID }) else { return }
        let old = messages[idx]
        let mergedBlocks = ChatMessageBlockBuilder.mergeRichBlocks(existingBlocks: old.blocks, incomingBlocks: incomingBlocks)
        updateMessageBlocksSnapshot(
            threadID: threadID,
            clientMessageID: clientMessageID,
            blocks: mergedBlocks
        )
    }

    func updateMessageBlocksSnapshot(
        threadID: UUID,
        clientMessageID: UUID,
        blocks: [ChatMessageBlock]
    ) {
        guard var messages = messagesByThread[threadID] else { return }
        guard let idx = messages.lastIndex(where: { $0.clientMessageID == clientMessageID }) else { return }
        let old = messages[idx]
        messages[idx] = ChatMessage(
            id: old.id,
            threadID: old.threadID,
            role: old.role,
            blocks: ChatMessageBlockBuilder.composeBlocks(blocks),
            clientMessageID: old.clientMessageID,
            serverMessageID: old.serverMessageID,
            deliveryState: old.deliveryState,
            createdAt: old.createdAt,
            serverUpdatedAt: Date(),
            isTombstone: old.isTombstone,
            modelName: old.modelName
        )
        messagesByThread[threadID] = messages
    }

    func setLoadingMore(_ loading: Bool, for threadID: UUID) {
        let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: true, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: current.hasMore, isLoadingMore: loading)
    }

    func hasMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.hasMore ?? false
    }

    func isLoadingMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.isLoadingMore ?? false
    }

    /// 打开会话时短暂保持底部视口锁，直到首屏 newest 窗口稳定落地。
    func beginBottomViewportLock(for threadID: UUID) {
        bottomViewportLockedThreadIDs.insert(threadID)
    }

    func endBottomViewportLock(for threadID: UUID) {
        bottomViewportLockedThreadIDs.remove(threadID)
    }

    func isBottomViewportLocked(for threadID: UUID) -> Bool {
        bottomViewportLockedThreadIDs.contains(threadID)
    }

    func requestScrollToBottom(for threadID: UUID) {
        scrollToBottomRequestGenerationByThread[threadID, default: 0] &+= 1
    }

    func scrollToBottomRequestGeneration(for threadID: UUID) -> UInt64 {
        scrollToBottomRequestGenerationByThread[threadID] ?? 0
    }

    func setDraft(_ text: String, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.text = text
        }
    }

    func draft(for threadID: UUID?) -> String {
        composerDraft(for: threadID).text
    }

    func composerDraft(for threadID: UUID?) -> ChatComposerDraft {
        guard let threadID else { return ChatComposerDraft() }
        return composerDrafts[threadID] ?? ChatComposerDraft()
    }

    func clearDraft(for threadID: UUID?) {
        let attachmentIDsToClear: [UUID]? = threadID.flatMap { id in
            composerDrafts[id]?.attachments.map(\.id)
        }
        updateComposerDraft(for: threadID) { draft in
            draft.text = ""
            draft.attachments = []
            draft.isShowingAttachmentMenu = false
            draft.isShowingPhotoPicker = false
            draft.isShowingCamera = false
            draft.previewSelection = nil
        }
        if let attachmentIDsToClear {
            for aid in attachmentIDsToClear {
                composerAttachmentUploadProgress.removeValue(forKey: aid)
                composerPreparedAttachmentStates.removeValue(forKey: aid)
            }
        } else {
            composerAttachmentUploadProgress = [:]
            composerPreparedAttachmentStates = [:]
        }
    }

    func setComposerAttachmentUploadProgress(id: UUID, progress: Double) {
        composerAttachmentUploadProgress[id] = progress
    }

    func clearComposerAttachmentUploadProgress() {
        composerAttachmentUploadProgress = [:]
    }

    func setComposerPreparedAttachmentState(id: UUID, _ state: ChatComposerPreparedAttachmentState) {
        composerPreparedAttachmentStates[id] = state
    }

    func composerPreparedAttachmentState(id: UUID) -> ChatComposerPreparedAttachmentState? {
        composerPreparedAttachmentStates[id]
    }

    func removeComposerPreparedAttachmentState(id: UUID) {
        composerPreparedAttachmentStates.removeValue(forKey: id)
    }

    func preparedAttachments(for threadID: UUID?) -> [ChatPreparedAttachment] {
        let draft = composerDraft(for: threadID)
        return draft.attachments.compactMap { attachment in
            composerPreparedAttachmentStates[attachment.id]?.prepared
        }
    }

    func hasBlockingPreparedAttachmentWork(for threadID: UUID?) -> Bool {
        let draft = composerDraft(for: threadID)
        guard draft.attachments.isEmpty == false else { return false }
        for attachment in draft.attachments {
            guard let state = composerPreparedAttachmentStates[attachment.id] else { continue }
            if state.phase == .success { continue }
            return true
        }
        return false
    }

    func clearComposer(for threadID: UUID?) {
        guard let threadID else { return }
        composerDrafts[threadID] = ChatComposerDraft()
    }

    func updateRuntimeFlags(
        for threadID: UUID?,
        update: (inout ChatComposerRuntimeFlags) -> Void
    ) {
        updateComposerDraft(for: threadID) { draft in
            update(&draft.runtimeFlags)
        }
    }

    func setSelectedChatModelName(_ name: String?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.runtimeFlags.selectedChatModelName = name
        }
    }

    func setAttachmentMenuPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingAttachmentMenu = isPresented
        }
    }

    func setPhotoPickerPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingPhotoPicker = isPresented
        }
    }

    func setCameraPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingCamera = isPresented
        }
    }

    func appendComposerAttachments(_ attachments: [ChatComposerAttachmentPreview], for threadID: UUID?) {
        guard attachments.isEmpty == false else { return }
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.append(contentsOf: attachments)
            draft.previewSelection = attachments.last?.id
        }
        for item in attachments {
            composerPreparedAttachmentStates[item.id] = .pending
            composerAttachmentUploadProgress[item.id] = 0
        }
    }

    func removeComposerAttachment(id: UUID, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.removeAll { $0.id == id }
            if draft.previewSelection == id {
                draft.previewSelection = draft.attachments.last?.id
            }
        }
        composerAttachmentUploadProgress.removeValue(forKey: id)
        composerPreparedAttachmentStates.removeValue(forKey: id)
    }

    func setPreviewSelection(_ attachmentID: UUID?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.previewSelection = attachmentID
        }
    }

    func setLoading(_ value: Bool) {
        isLoading = value
    }

    func setSending(_ value: Bool) {
        isSending = value
    }

    func setError(_ message: String?) {
        setError(message, for: selectedThreadID)
    }

    func setError(_ message: String?, for threadID: UUID?) {
        guard let threadID else { return }
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty == false {
            threadErrorMessages[threadID] = trimmed
        } else {
            threadErrorMessages.removeValue(forKey: threadID)
        }
    }

    func errorMessage(for threadID: UUID?) -> String? {
        guard let threadID else { return nil }
        return threadErrorMessages[threadID]
    }

    /// 会话切换时清空内存态，避免短暂展示上一账号的会话列表与消息。
    func resetForSessionSwitch() {
        threadItems = []
        messagesByThread = [:]
        selectedThreadID = nil
        isLoading = false
        isSending = false
        threadErrorMessages = [:]
        composerDrafts = [:]
        composerAttachmentUploadProgress = [:]
        composerPreparedAttachmentStates = [:]
        streamingAssistants = [:]
        messagePagingByThread = [:]
        streamingContentGeneration &+= 1
    }

    func startStreamingAssistant(
        threadID: UUID,
        clientMessageID: UUID,
        kind: ChatMessageKind,
        createdAt: Date = Date()
    ) {
        streamingAssistants[threadID] = StreamingAssistant(
            threadID: threadID,
            clientMessageID: clientMessageID,
            state: .initial(kind: kind),
            createdAt: createdAt
        )
        streamingContentGeneration &+= 1
    }

    func updateStreamingAssistant(
        threadID: UUID,
        delta: ChatAssistantPartialDelta
    ) {
        guard var streaming = streamingAssistants[threadID] else { return }
        let changed = streamingReducer.reduce(
            state: &streaming.state,
            delta: delta
        )
        guard changed else { return }
        streamingAssistants[threadID] = streaming
        streamingContentGeneration &+= 1
    }

    func updateStreamingAssistant(
        threadID: UUID,
        kind: ChatMessageKind,
        content: String,
        reasoningContent: String?,
        toolName: String?,
        toolContent: String?
    ) {
        updateStreamingAssistant(
            threadID: threadID,
            delta: ChatAssistantPartialDelta(
                answer: content,
                reasoning: reasoningContent,
                kind: kind,
                toolName: toolName,
                toolContent: toolContent,
                toolCallID: nil
            )
        )
    }

    func finishStreamingAssistant(threadID: UUID) {
        streamingAssistants[threadID] = nil
    }

    private func updateComposerDraft(
        for threadID: UUID?,
        update: (inout ChatComposerDraft) -> Void
    ) {
        guard let threadID else { return }
        var draft = composerDrafts[threadID] ?? ChatComposerDraft()
        update(&draft)
        composerDrafts[threadID] = draft
    }

    func mergeStreamingAssistantAttachments(
        threadID: UUID,
        incomingBlocks: [ChatMessageBlock]
    ) {
        guard incomingBlocks.isEmpty == false else { return }
        guard var streaming = streamingAssistants[threadID] else { return }
        let changed = streamingReducer.mergeAttachments(state: &streaming.state, incomingBlocks: incomingBlocks)
        guard changed else { return }
        streamingAssistants[threadID] = streaming
        streamingContentGeneration &+= 1
    }
    /// 合并流式助手的展示内容（更新UI展示用）
    /// - Parameters:
    ///   - threadID: 对话线程唯一标识
    ///   - incomingBlocks: 新接收到的消息块数据
    func mergeStreamingAssistantPresentation(
        threadID: UUID,
        incomingBlocks: [ChatMessageBlock]
    ) {
        // 无新消息块时直接返回，不执行后续逻辑
        guard incomingBlocks.isEmpty == false else { return }
        
        // 根据线程ID获取对应的流式助手实例，不存在则直接返回
        guard var streaming = streamingAssistants[threadID] else { return }
        
        // 调用reducer合并新的消息块到当前流式状态中，并返回是否发生了变更
        let changed = streamingReducer.mergePresentation(
            state: &streaming.state,
            incomingBlocks: incomingBlocks
        )
        
        // 状态无变更时直接返回，不更新数据
        guard changed else { return }
        
        // 将更新后的流式助手状态存回字典
        streamingAssistants[threadID] = streaming
        
        // 流式内容生成计数 +1（用于统计/刷新标记）
        streamingContentGeneration &+= 1
    }
    
}
