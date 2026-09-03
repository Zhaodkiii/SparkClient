import SwiftUI
import Combine

/// 聊天会话全局状态管理仓库
/// 遵循 MainActor 保证UI线程执行，ObservableObject 对外发布状态变更驱动UI刷新
@MainActor
final class ChatStateStore: ObservableObject {
    /// 单条会话的消息分页状态结构体
    private struct MessagePaging: Sendable {
        /// 是否还有更多历史消息可加载
        var hasMore: Bool
        /// 是否正在加载更多历史消息
        var isLoadingMore: Bool
    }

    // MARK: - 会话列表 状态
    /// 所有聊天会话列表数据（对外只读）
    @Published private(set) var threadItems: [ChatThreadListItem] = []
    /// 按会话ID分组存储对应的消息列表（key: 会话ID, value: 消息数组）
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    /// 当前选中的会话ID
    @Published private(set) var selectedThreadID: UUID?
    /// 全局加载状态（会话/消息列表加载）
    @Published private(set) var isLoading = false
    /// 消息发送中状态
    @Published private(set) var isSending = false
    /// 按会话ID记录对应会话的错误提示文案
    @Published private(set) var threadErrorMessages: [UUID: String] = [:]

    // MARK: - 输入框草稿 & 附件 状态
    /// 按会话ID存储输入框草稿内容（文本、附件、配置等）
    @Published private var composerDrafts: [UUID: ChatComposerDraft] = [:]
    /// 新会话草稿的默认启动偏好。
    private var composerStartupPreferences: ChatComposerStartupPreferences = .default
    /// 待发送附件上传进度（由发送业务逻辑实时回写更新）
    @Published private(set) var composerAttachmentUploadProgress: [UUID: Double] = [:]
    /// 选图后预处理/ OCR 附件状态（按附件ID维度管理）
    @Published private(set) var composerPreparedAttachmentStates: [UUID: ChatComposerPreparedAttachmentState] = [:]

    // MARK: - 分页 & 滚动 & 视口锁定 状态
    /// 按会话ID存储对应会话的消息分页配置
    @Published private var messagePagingByThread: [UUID: MessagePaging] = [:]
    /// 底部视口锁定的会话ID集合（防止会话切换/加载时页面异常滚动）
    @Published private var bottomViewportLockedThreadIDs: Set<UUID> = []
    /// 会话触底滚动请求计数：数值自增触发视图强制滚动到最新消息（如发送消息后）
    @Published private(set) var scrollToBottomRequestGenerationByThread: [UUID: UInt64] = [:]

    // MARK: - 计算属性
    /// 当前选中的会话实体
    var selectedThread: ChatThread? {
        threadItems.first(where: { $0.id == selectedThreadID })?.thread
    }

    /// 当前选中会话的所有展示消息
    var selectedMessages: [ChatMessage] {
        guard let selectedThreadID else { return [] }
        return conversationListItems(for: selectedThreadID)
    }

    // MARK: - 消息数据查询
    /// 获取指定会话纯本地持久化消息（不含流式占位消息）
    func persistedMessages(for threadID: UUID) -> [ChatMessage] {
        messagesByThread[threadID] ?? []
    }

    /// 获取会话列表最终展示消息（持久化消息 + 流式消息，避免列表ID抖动）
    func conversationListItems(for threadID: UUID) -> [ChatMessage] {
        messagesByThread[threadID] ?? []
    }

    // MARK: - 会话列表 操作
    /// 全量更新会话列表，并自动修正选中态
    func setThreads(_ items: [ChatThreadListItem]) {
        threadItems = items
        // 如果当前选中会话已不在列表中，自动切换为列表第一个
        if let selectedThreadID, items.contains(where: { $0.id == selectedThreadID }) == false {
            self.selectedThreadID = items.first?.id
        }
        // 无选中会话时，默认选中第一条
        if self.selectedThreadID == nil {
            self.selectedThreadID = items.first?.id
        }
    }

    /// 新增/更新单条会话，并按最新消息时间倒序重排（数据库通知局部刷新使用）
    func upsertThreadListItem(_ item: ChatThreadListItem) {
        // 移除同ID旧数据，追加新数据
        var next = threadItems.filter { $0.id != item.id }
        next.append(item)
        // 按最新消息时间降序排序
        threadItems = next.sorted { $0.latestMessageAt > $1.latestMessageAt }
        // 无选中会话时默认选中第一条
        if selectedThreadID == nil {
            selectedThreadID = threadItems.first?.id
        }
    }

    /// 移除指定会话（软删除场景），并同步修正选中态
    func removeThreadListItem(id: UUID) {
        threadItems.removeAll { $0.id == id }
        // 删除的是当前选中会话，则自动选中列表第一条
        if selectedThreadID == id {
            selectedThreadID = threadItems.first?.id
        }
    }

    /// 手动设置当前选中的会话ID
    func setSelectedThreadID(_ threadID: UUID?) {
        selectedThreadID = threadID
    }

    // MARK: - 新建对话触发标记（CHAT-000028 3.3）
    /// 进程内「本次新建对话」标记（threadID -> 创建时间）：
    /// 用于区分新建对话首次初始化（可触发科普问题生成）与重新进入旧对话（只允许修复）。
    /// 标记仅进程内有效，App 重启后自然失效（重启进入视为重新进入）。
    private var newlyCreatedThreadMarkers: [UUID: Date] = [:]
    /// 标记有效期：超时后进入不再视为新建链路
    private static let newlyCreatedMarkerLifetime: TimeInterval = 120

    /// 标记 thread 为本次新建对话（由创建对话编排层调用）。
    func markThreadAsNewlyCreated(_ threadID: UUID) {
        newlyCreatedThreadMarkers[threadID] = Date()
    }

    /// 是否仍带有未消费（且未过期）的新建标记。
    func isThreadMarkedAsNewlyCreated(_ threadID: UUID) -> Bool {
        newlyCreatedThreadCreatedAt(threadID) != nil
    }

    /// 清除新建标记（新建链路 ensure + 生成注册完成后调用；
    /// 保持期间可阻止并发消息加载中的 reenter repair 误修复新插入的 generating 卡片）。
    func clearThreadWasJustCreatedMarker(_ threadID: UUID) {
        newlyCreatedThreadMarkers[threadID] = nil
    }

    private func newlyCreatedThreadCreatedAt(_ threadID: UUID) -> Date? {
        guard let createdAt = newlyCreatedThreadMarkers[threadID] else { return nil }
        guard Date().timeIntervalSince(createdAt) <= Self.newlyCreatedMarkerLifetime else {
            newlyCreatedThreadMarkers[threadID] = nil
            return nil
        }
        return createdAt
    }

    // MARK: - 消息数据 全量/更新/追加
    /// 全量替换指定会话的消息列表，并更新分页「是否还有更多」状态
    func setMessages(
        _ messages: [ChatMessage],
        for threadID: UUID,
        hasMore: Bool? = nil
    ) {
        var previousByClientID: [UUID: ChatMessage] = [:]
        for message in messagesByThread[threadID] ?? [] {
            previousByClientID[message.clientMessageID] = message
        }
        let mergedMessages = messages.map { message in
            guard let previous = previousByClientID[message.clientMessageID] else { return message }
            return message.mergingLocalInlineToolInteractionBlocks(from: previous)
        }
        messagesByThread[threadID] = mergedMessages
        if let hasMore {
            // 保留原有加载状态，仅更新是否有更多
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
        }
    }

    /// 增量更新已有消息（根据客户端消息ID匹配替换，局部刷新）
    func updateMessages(_ messages: [ChatMessage], for threadID: UUID) {
        guard messages.isEmpty == false else { return }
        var current = messagesByThread[threadID] ?? []
        guard current.isEmpty == false else { return }
        // 转为字典：clientMessageID -> 消息实体，提升查询效率
        let replacements = Dictionary(uniqueKeysWithValues: messages.map { ($0.clientMessageID, $0) })
        var changed = false

        // 遍历替换变更的消息
        for index in current.indices {
            let id = current[index].clientMessageID
            if let replacement = replacements[id]?.mergingLocalInlineToolInteractionBlocks(from: current[index]),
               replacement != current[index] {
                current[index] = replacement
                changed = true
            }
        }
        // 有变更才回写，减少状态刷新
        if changed {
            messagesByThread[threadID] = current
        }
    }

    /// 向前追加历史消息（加载更早的消息，插在列表头部）
    func prependMessages(_ messages: [ChatMessage], for threadID: UUID, hasMore: Bool) {
        // 无新消息仅更新分页状态
        guard messages.isEmpty == false else {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
            return
        }
        let current = messagesByThread[threadID] ?? []
        // 去重：过滤掉列表中已存在的消息
        let existingIDs = Set(current.map(\.id))
        let mergedPrefix = messages.filter { existingIDs.contains($0.id) == false }
        // 新消息拼接到头部
        messagesByThread[threadID] = mergedPrefix + current
        // 更新分页状态
        let paging = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: paging.isLoadingMore)
    }

    // MARK: - 消息分页状态管理
    /// 设置指定会话「加载更多」的加载中状态
    func setLoadingMore(_ loading: Bool, for threadID: UUID) {
        let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: true, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: current.hasMore, isLoadingMore: loading)
    }

    /// 查询指定会话是否还有更多历史消息
    func hasMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.hasMore ?? false
    }

    /// 查询指定会话是否正在加载更多历史消息
    func isLoadingMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.isLoadingMore ?? false
    }

    // MARK: - 底部视口锁定（滚动防护）
    /// 开启指定会话底部视口锁定（会话初始化/加载时防止异常滚动）
    func beginBottomViewportLock(for threadID: UUID) {
        bottomViewportLockedThreadIDs.insert(threadID)
    }

    /// 解除指定会话底部视口锁定
    func endBottomViewportLock(for threadID: UUID) {
        bottomViewportLockedThreadIDs.remove(threadID)
    }

    /// 判断指定会话是否处于底部视口锁定状态
    func isBottomViewportLocked(for threadID: UUID) -> Bool {
        bottomViewportLockedThreadIDs.contains(threadID)
    }

    // MARK: - 滚动到底部 触发逻辑
    /// 发起「滚动到最新消息」请求（计数自增驱动视图刷新滚动）
    func requestScrollToBottom(for threadID: UUID) {
        scrollToBottomRequestGenerationByThread[threadID, default: 0] &+= 1
    }

    /// 获取当前会话滚动请求计数
    func scrollToBottomRequestGeneration(for threadID: UUID) -> UInt64 {
        scrollToBottomRequestGenerationByThread[threadID] ?? 0
    }

    // MARK: - Q6 新消息计数（CHAT-000056，仅 UI 临时状态）
    /// 按会话ID记录「用户阅读历史期间到达、尚未跟随展示」的远端新消息条数。
    /// 不等同于普通会话未读数：贴底自动跟随时为 0；阅读历史时按真实新增条数累加；
    /// 点击「有新消息」按钮、手动回到底部、切 thread、退出详情、成员/账号切换时清理。
    /// 院内名医目录不读取该值。
    @Published private(set) var unseenRemoteMessageCountByThread: [UUID: Int] = [:]

    /// 查询指定会话的未展示新消息条数
    func unseenRemoteMessageCount(for threadID: UUID) -> Int {
        unseenRemoteMessageCountByThread[threadID] ?? 0
    }

    /// 按真实新增消息条数累加（同一批远端消息合并后一次性累加，不按 WebSocket hint 次数）
    func addUnseenRemoteMessageCount(_ delta: Int, for threadID: UUID) {
        guard delta > 0 else { return }
        unseenRemoteMessageCountByThread[threadID, default: 0] += delta
    }

    /// 清零指定会话的新消息计数
    func clearUnseenRemoteMessageCount(for threadID: UUID) {
        unseenRemoteMessageCountByThread.removeValue(forKey: threadID)
    }

    /// 清空全部新消息计数（成员切换等 UI 临时状态整体失效场景）
    func clearAllUnseenRemoteMessageCounts() {
        guard unseenRemoteMessageCountByThread.isEmpty == false else { return }
        unseenRemoteMessageCountByThread = [:]
    }

    // MARK: - 输入框草稿 文本管理
    /// 设置指定会话输入框草稿文本
    func setDraft(_ text: String, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.text = text
        }
    }

    /// 获取指定会话输入框草稿文本
    func draft(for threadID: UUID?) -> String {
        composerDraft(for: threadID).text
    }

    /// 获取指定会话完整草稿对象（无则返回空草稿）
    func composerDraft(for threadID: UUID?) -> ChatComposerDraft {
        guard let threadID else { return ChatComposerDraft() }
        return composerDrafts[threadID] ?? makeDefaultComposerDraft()
    }

    /// 清空输入框全部内容（文本、附件、健康资料引用等）
    func clearDraft(for threadID: UUID?) {
        clearComposerSurface(for: threadID, includingHealthResourceRefs: true)
    }

    /// 发送消息后：仅清空文本和附件，保留AI检索的健康资料引用
    func clearComposerTextAndAttachments(for threadID: UUID?) {
        clearComposerSurface(for: threadID, includingHealthResourceRefs: false)
    }

    /// 内部统一清空输入面板逻辑
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - includingHealthResourceRefs: 是否同时清空健康资料引用
    private func clearComposerSurface(for threadID: UUID?, includingHealthResourceRefs: Bool) {
        // 收集当前草稿内所有附件ID，用于后续清理上传状态
        let attachmentIDsToClear: [UUID]? = threadID.flatMap { id in
            composerDrafts[id]?.attachments.map(\.id)
        }

        // 重置草稿基础内容与弹窗状态
        updateComposerDraft(for: threadID) { draft in
            draft.text = ""
            draft.attachments = []
            // 按需清空健康资料引用
            if includingHealthResourceRefs {
                draft.pendingHealthResourceRefs = []
            }
            draft.isShowingAttachmentMenu = false
            draft.isShowingPhotoPicker = false
            draft.isShowingCamera = false
            draft.previewSelection = nil
        }

        // 清理附件上传进度、预处理状态
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

    // MARK: - 附件上传 & 预处理状态
    /// 更新单条附件的上传进度
    func setComposerAttachmentUploadProgress(id: UUID, progress: Double) {
        composerAttachmentUploadProgress[id] = progress
    }

    /// 清空所有附件上传进度
    func clearComposerAttachmentUploadProgress() {
        composerAttachmentUploadProgress = [:]
    }

    /// 设置指定附件的预处理状态（选图/OCR/解析）
    func setComposerPreparedAttachmentState(id: UUID, _ state: ChatComposerPreparedAttachmentState) {
        composerPreparedAttachmentStates[id] = state
    }

    /// 查询指定附件的预处理状态
    func composerPreparedAttachmentState(id: UUID) -> ChatComposerPreparedAttachmentState? {
        composerPreparedAttachmentStates[id]
    }

    /// 移除指定附件的预处理状态记录
    func removeComposerPreparedAttachmentState(id: UUID) {
        composerPreparedAttachmentStates.removeValue(forKey: id)
    }

    /// 获取指定会话所有已完成预处理的附件
    func preparedAttachments(for threadID: UUID?) -> [ChatPreparedAttachment] {
        let draft = composerDraft(for: threadID)
        return draft.attachments.compactMap { attachment in
            composerPreparedAttachmentStates[attachment.id]?.prepared
        }
    }

    /// 判断当前是否有附件正在预处理/上传（阻塞发送操作）
    func hasBlockingPreparedAttachmentWork(for threadID: UUID?) -> Bool {
        let draft = composerDraft(for: threadID)
        guard draft.attachments.isEmpty == false else { return false }
        // 存在非成功状态的附件，判定为阻塞
        for attachment in draft.attachments {
            guard let state = composerPreparedAttachmentStates[attachment.id] else { continue }
            if state.phase == .success { continue }
            return true
        }
        return false
    }

    /// 彻底重置指定会话的整个输入草稿
    func clearComposer(for threadID: UUID?) {
        guard let threadID else { return }
        composerDrafts[threadID] = makeDefaultComposerDraft()
    }

    // MARK: - 输入框运行时配置 & 弹窗状态
    /// 批量更新输入框运行时标识
    func updateRuntimeFlags(
        for threadID: UUID?,
        update: (inout ChatComposerRuntimeFlags) -> Void
    ) {
        updateComposerDraft(for: threadID) { draft in
            update(&draft.runtimeFlags)
        }
    }

    /// 设置当前会话选中的AI模型名称
    func setSelectedChatModelName(_ name: String?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.runtimeFlags.selectedChatModelName = name
        }
    }

    /// 更新新会话草稿的默认启动偏好。
    func setComposerStartupPreferences(_ preferences: ChatComposerStartupPreferences) {
        composerStartupPreferences = preferences
    }

    /// 控制附件菜单弹窗显示/隐藏
    func setAttachmentMenuPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingAttachmentMenu = isPresented
        }
    }

    /// 控制相册选择器弹窗显示/隐藏
    func setPhotoPickerPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingPhotoPicker = isPresented
        }
    }

    /// 控制相机弹窗显示/隐藏
    func setCameraPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingCamera = isPresented
        }
    }

    // MARK: - 附件增删 & 预览选中
    /// 批量追加附件到输入框
    func appendComposerAttachments(_ attachments: [ChatComposerAttachmentPreview], for threadID: UUID?) {
        guard attachments.isEmpty == false else { return }
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.append(contentsOf: attachments)
            // 默认选中最后一个新增附件作为预览项
            draft.previewSelection = attachments.last?.id
        }
        // 初始化附件状态：待处理 + 进度0
        for item in attachments {
            composerPreparedAttachmentStates[item.id] = .pending
            composerAttachmentUploadProgress[item.id] = 0
        }
    }

    /// 移除指定附件
    func removeComposerAttachment(id: UUID, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.removeAll { $0.id == id }
            // 如果删除的是当前预览项，自动切换为最后一个附件
            if draft.previewSelection == id {
                draft.previewSelection = draft.attachments.last?.id
            }
        }
        // 同步清理该附件的进度、状态记录
        composerAttachmentUploadProgress.removeValue(forKey: id)
        composerPreparedAttachmentStates.removeValue(forKey: id)
    }

    /// 设置当前附件预览选中项
    func setPreviewSelection(_ attachmentID: UUID?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.previewSelection = attachmentID
        }
    }

    // MARK: - 健康资料引用（AI工具检索资料）
    /// 批量追加健康资料引用（限制最大数量、去重）
    func appendHealthResourceRefs(_ refs: [HealthResourceRef], for threadID: UUID?) {
        guard refs.isEmpty == false else { return }
        updateComposerDraft(for: threadID) { draft in
            for ref in refs {
                // 超出最大数量则终止添加
                guard draft.pendingHealthResourceRefs.count < HealthResourceSendValidator.maxRefs else { break }
                // 已存在则跳过（去重）
                guard draft.pendingHealthResourceRefs.contains(where: { $0.id == ref.id }) == false else { continue }
                draft.pendingHealthResourceRefs.append(ref)
            }
        }
    }

    /// 移除单条健康资料引用
    func removeHealthResourceRef(_ ref: HealthResourceRef, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.pendingHealthResourceRefs.removeAll { $0.id == ref.id }
        }
    }

    /// 清空所有健康资料引用
    func clearHealthResourceRefs(for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.pendingHealthResourceRefs = []
        }
    }

    /// 根据用户ID过滤/清空健康资料引用（切换用户场景）
    func pruneHealthResourceRefs(matchingMemberID memberID: Int?, for threadID: UUID?) {
        guard let memberID, memberID > 0 else {
            clearHealthResourceRefs(for: threadID)
            return
        }
        // 只保留对应当前用户的资料引用
        updateComposerDraft(for: threadID) { draft in
            draft.pendingHealthResourceRefs.removeAll { $0.memberID != memberID }
        }
    }

    // MARK: - 全局加载/发送/错误状态
    /// 设置全局加载状态
    func setLoading(_ value: Bool) {
        isLoading = value
    }

    /// 设置消息发送中状态
    func setSending(_ value: Bool) {
        isSending = value
    }

    /// 为当前选中会话设置错误提示
    func setError(_ message: String?) {
        setError(message, for: selectedThreadID)
    }

    /// 为指定会话设置/清空错误提示（自动去除首尾空白）
    func setError(_ message: String?, for threadID: UUID?) {
        guard let threadID else { return }
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty == false {
            threadErrorMessages[threadID] = trimmed
        } else {
            threadErrorMessages.removeValue(forKey: threadID)
        }
    }

    /// 获取指定会话的错误文案
    func errorMessage(for threadID: UUID?) -> String? {
        guard let threadID else { return nil }
        return threadErrorMessages[threadID]
    }

    // MARK: - 账号切换 全量重置
    /// 切换登录账号时，清空所有内存状态，防止数据串号
    func resetForSessionSwitch() {
        threadItems = []
        messagesByThread = [:]
        selectedThreadID = nil
        isLoading = false
        isSending = false
        threadErrorMessages = [:]
        composerDrafts = [:]
        composerStartupPreferences = .default
        composerAttachmentUploadProgress = [:]
        composerPreparedAttachmentStates = [:]
        messagePagingByThread = [:]
        unseenRemoteMessageCountByThread = [:]
    }

    // MARK: - 内部工具方法
    /// 通用草稿更新工具：获取/创建草稿 -> 执行修改 -> 回写
    private func updateComposerDraft(
        for threadID: UUID?,
        update: (inout ChatComposerDraft) -> Void
    ) {
        guard let threadID else { return }
        // 无草稿则新建带默认启动偏好的草稿
        var draft = composerDrafts[threadID] ?? makeDefaultComposerDraft()
        update(&draft)
        composerDrafts[threadID] = draft
    }

    private func makeDefaultComposerDraft() -> ChatComposerDraft {
        var draft = ChatComposerDraft()
        draft.runtimeFlags = ChatComposerRuntimeFlags(startupPreferences: composerStartupPreferences)
        return draft
    }
}
