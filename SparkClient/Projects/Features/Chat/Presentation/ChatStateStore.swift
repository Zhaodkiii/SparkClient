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
    @Published private var messagePagingByThread: [UUID: MessagePaging] = [:]
    @Published private var bottomViewportLockedThreadIDs: Set<UUID> = []
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
        messagesByThread[threadID] ?? []
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

    func setMessages(
        _ messages: [ChatMessage],
        for threadID: UUID,
        hasMore: Bool? = nil
    ) {
        messagesByThread[threadID] = messages
        if let hasMore {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
        }
    }

    func updateMessages(_ messages: [ChatMessage], for threadID: UUID) {
        guard messages.isEmpty == false else { return }
        var current = messagesByThread[threadID] ?? []
        guard current.isEmpty == false else { return }
        let replacements = Dictionary(uniqueKeysWithValues: messages.map { ($0.clientMessageID, $0) })
        var changed = false
        for index in current.indices {
            let id = current[index].clientMessageID
            if let replacement = replacements[id], replacement != current[index] {
                current[index] = replacement
                changed = true
            }
        }
        if changed {
            messagesByThread[threadID] = current
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
        messagePagingByThread = [:]
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
}
