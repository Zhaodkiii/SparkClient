import Foundation

/// 编排聊天同步子系统：REST/WebSocket 同步引擎 + 附件落盘管线，供生命周期与用例统一入口。
actor ChatSyncSupervisor {
    private let syncEngine: ChatSyncEngine
    private let attachmentPipeline: ChatAttachmentPipeline
    private nonisolated(unsafe) var localChangeObserver: NSObjectProtocol?
    private var debouncedOutboxTask: Task<Void, Never>?
    private var debouncedThreadPushTasks: [UUID: Task<Void, Never>] = [:]

    init(syncEngine: ChatSyncEngine, attachmentPipeline: ChatAttachmentPipeline) {
        self.syncEngine = syncEngine
        self.attachmentPipeline = attachmentPipeline
        self.localChangeObserver = NotificationCenter.default.addObserver(
            forName: .sparkChatDatabaseDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let event = notification.chatConversationChangeEvent else { return }
            switch event.kind {
            case .messagesAppended, .messagesUpdated, .messagesMerged:
                guard event.affectsThreadList else { return }
                Task { await self?.scheduleOutboxPush(reason: event.kind.rawValue) }
            case .threadsChanged:
                guard let threadID = event.threadID else { return }
                Task { await self?.scheduleThreadPush(threadID: threadID) }
            }
        }
    }

    deinit {
        if let localChangeObserver {
            NotificationCenter.default.removeObserver(localChangeObserver)
        }
        debouncedOutboxTask?.cancel()
        for task in debouncedThreadPushTasks.values {
            task.cancel()
        }
    }

    func syncNow() async throws {
        try await syncEngine.syncNow()
        await attachmentPipeline.processPendingJobs(limit: 8)
    }

    func syncNowWithPull() async throws {
        try await syncEngine.syncNowWithPull()
        await attachmentPipeline.processPendingJobs(limit: 24)
    }

    func refreshThreadListIncremental() async throws {
        try await syncEngine.refreshThreadListIncremental()
    }

    func pullThreadMessagesIncrementalOnOpen(threadID: UUID) async throws {
        try await syncEngine.pullThreadMessagesIncrementalOnOpen(threadID: threadID)
    }

    private func scheduleOutboxPush(reason: String) {
        debouncedOutboxTask?.cancel()
        debouncedOutboxTask = Task { [syncEngine, attachmentPipeline] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard Task.isCancelled == false else { return }
            do {
                try await syncEngine.pushOutboxOnly()
                await attachmentPipeline.processPendingJobs(limit: 8)
            } catch {
                // SyncEngine owns retry state through deliveryState; this observer is only a debounce trigger.
                ConsoleLogger().debug("聊天 outbox 自动上送失败，reason=\(reason), error=\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func scheduleThreadPush(threadID: UUID) {
        debouncedThreadPushTasks[threadID]?.cancel()
        debouncedThreadPushTasks[threadID] = Task { [syncEngine] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard Task.isCancelled == false else { return }
            try? await syncEngine.pushSingleThread(threadID: threadID)
            try? await syncEngine.syncNow()
        }
    }

    func startRealtimeSync() async {
        await syncEngine.startRealtimeSync()
    }

    func stopRealtimeSync() async {
        await syncEngine.stopRealtimeSync()
    }

    /// CHAT-000056 Q3：账号启动、连接成功、前台恢复、网络恢复统一的全局补偿入口。
    /// 非阻塞调度：由同步引擎 single-flight + dirty 合并并发触发，不增加定时轮询。
    nonisolated func scheduleGlobalCompensation(source: ChatGlobalCompensationSource) {
        Task { [syncEngine] in
            await syncEngine.requestGlobalCompensation(source: source)
        }
    }

    /// 登录/会话引导后可选调用：不阻塞 UI 地消化积压图片任务。
    func kickAttachmentDrain() async {
        await attachmentPipeline.processPendingJobs(limit: 32)
    }
}
