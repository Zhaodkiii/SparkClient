import Foundation

actor ChatSyncEngine {
    private enum SyncScope: Hashable {
        case global
        case thread(UUID)
    }

    private enum SyncPaging {
        static let threadPageLimit = 100
        static let messagePageLimit = 200
        static let maxPagesPerRun = 20
    }

    private let repository: any ChatRepository
    private let outboxStore: ChatOutboxStore
    private let remoteAPI: SparkChatRemoteAPI
    private let realtimeClient: ChatRealtimeSyncClient?
    private let inboundPipeline: ChatInboundPipeline
    private let outboxPipeline: ChatOutboxPipeline
    private let logger: Logger
    private var inflightSyncTasks: [SyncScope: Task<Void, Error>] = [:]

    /// CHAT-000056：实时拉取调度器（per-thread debounce/dirty/retry + 全局补偿状态机）。
    /// lazy 以便闭包在 init 完成后捕获 engine。
    private lazy var realtimeScheduler = ChatRealtimePullScheduler(
        pullThread: { [weak self] threadID, forceFullRefresh in
            guard let self else { return }
            try await self.performRealtimeThreadPull(threadID: threadID, forceFullRefresh: forceFullRefresh)
        },
        pullGlobal: { [weak self] in
            guard let self else { return }
            try await self.performGlobalCompensationCycle()
        },
        classifyError: { error in
            Self.classifyRealtimePullError(error)
        },
        logger: logger
    )

    private static var syncCursorFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    init(
        repository: any ChatRepository,
        outboxStore: ChatOutboxStore,
        remoteAPI: SparkChatRemoteAPI,
        realtimeClient: ChatRealtimeSyncClient? = nil,
        mergePolicy: ChatMergePolicy,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.realtimeClient = realtimeClient
        self.inboundPipeline = ChatInboundPipeline(repository: repository, mergeEngine: mergePolicy)
        self.outboxPipeline = ChatOutboxPipeline(
            repository: repository,
            outboxStore: outboxStore,
            remoteAPI: remoteAPI,
            logger: logger
        )
        self.logger = logger
    }

    /// 同步（仅上送，不拉取）：
    /// 1) 上送本地线程删除事件；
    /// 2) 上送 outbox 消息。
    func syncNow() async throws {
        try await runSingleFlight(scope: .global) { engine in
            try await engine.performGlobalSync()
        }
    }

    /// 手动刷新同步：上送 + 拉取未同步的线程与消息。
    func syncNowWithPull() async throws {
        try await runSingleFlight(scope: .global) { engine in
            try await engine.performManualRefreshSync()
        }
    }

    /// 对话列表下拉刷新：只拉取远端线程元数据增量（标题、更新时间等）。
    /// 不拉取各会话消息正文，也不触发附件后台下载；消息与图片在进入会话后按需同步/懒加载。
    /// 不主动上送本地 outbox，避免用户只是刷新列表时产生写请求。
    func refreshThreadListIncremental() async throws {
        try await runSingleFlight(scope: .global) { engine in
            _ = try await engine.pullThreadDeltas(
                cursor: await engine.repository.loadThreadSyncCursor()?.value
            )
        }
    }

    /// 将已经获得的远端消息交给现有入站管线幂等合并。
    func applyAlreadyFetchedMessages(
        _ messages: [ChatMessage],
        enqueueAttachmentDownloadJobs: Bool
    ) async {
        logger.debug(
            "CHAT-000061 apply_fetched_messages count=\(messages.count) threads=\(Set(messages.map(\.threadID)).count)",
            module: .general
        )
        guard messages.isEmpty == false else { return }
        await inboundPipeline.applyRemoteMessages(
            messages,
            enqueueAttachmentDownloadJobs: enqueueAttachmentDownloadJobs
        )
    }

    /// 进入会话：拉取当前会话消息增量。
    /// 本地已有疑似医生 assistant 却缺 `sender` 时，清 cursor 全量回填一次，避免旧缓存永远补不上身份。
    func pullThreadMessagesIncrementalOnOpen(threadID: UUID) async throws {
        try await runSingleFlight(scope: .thread(threadID)) { engine in
            let needsSenderBackfill = await engine.needsDoctorSenderBackfill(threadID: threadID)
            let cursor: String?
            if needsSenderBackfill {
                await engine.repository.deleteMessageSyncCursor(for: threadID)
                cursor = nil
            } else {
                let localCount = await engine.repository.countMessages(threadID: threadID)
                if localCount == 0 {
                    cursor = nil
                } else if let persisted = await engine.repository.loadMessageSyncCursor(for: threadID)?.value {
                    cursor = persisted
                } else {
                    cursor = await engine.repository.latestServerActivity(for: threadID).map(Self.formatSyncCursor)
                }
            }
            try await engine.pullAndMergeAllowingMissingRemoteThread(cursor: cursor, threadID: threadID)
            if needsSenderBackfill {
                Self.markDoctorSenderBackfillAttempted(threadID: threadID)
            }
        }
    }

    /// 仅上送待同步消息，不拉取（发送成功/重试等路径使用）。
    func pushOutboxOnly() async throws {
        try await runSingleFlight(scope: .global) { engine in
            engine.logger.debug("聊天仅上送 outbox", module: .general)
            try await engine.pushPendingThreadDeletions()
//            try await engine.pushThreads()
            try await engine.pushOutbox()
        }
    }

    /// 仅上送指定会话的元数据（单会话变更路径，避免全量推送）。
    func pushSingleThread(threadID: UUID) async throws {
        logger.debug("上送单会话元数据，thread=\(shortID(threadID))", module: .general)
        try await outboxPipeline.pushThread(threadID: threadID)
    }

    func startRealtimeSync() async {
        guard let realtimeClient else { return }
        await realtimeClient.start(
            onSyncHint: { [weak self] hint in
                guard let self else { return }
                Task {
                    await self.handleRealtimeHint(hint)
                }
            },
            onConnected: { [weak self] in
                guard let self else { return }
                Task {
                    // Q3：WebSocket 每次连接成功都触发全局补偿。
                    await self.requestGlobalCompensation(source: .realtimeConnected)
                }
            }
        )
    }

    func stopRealtimeSync() async {
        // 账号切换/登出：先取消调度与重连，旧任务结果不得再改动新账号调度状态。
        await realtimeScheduler.cancelAll()
        await realtimeClient?.stop()
    }

    /// CHAT-000056 Q3：账号启动、连接成功、前台恢复、网络恢复统一的全局补偿入口。
    func requestGlobalCompensation(source: ChatGlobalCompensationSource) async {
        await realtimeScheduler.requestGlobalCompensation(source: source)
    }

    private func handleRealtimeHint(_ hint: ChatSyncHint) async {
        await realtimeScheduler.handleHint(hint)
    }

    // MARK: - CHAT-000056 实时拉取

    /// Q1/Q2：实时 hint 驱动的 thread 定向增量拉取。
    ///
    /// 与现有 single-flight 的关系：先等待进行中的全局任务与同 thread 任务结束，再执行一次
    /// “hint 到达之后发起”的拉取，保证服务端已提交的消息必被本轮请求覆盖，不被复用语义吞掉。
    private func performRealtimeThreadPull(threadID: UUID, forceFullRefresh: Bool) async throws {
        while let globalTask = inflightSyncTasks[.global] {
            try? await globalTask.value
        }
        while let existing = inflightSyncTasks[.thread(threadID)] {
            try? await existing.value
        }

        let task = Task { () throws -> Void in
            let cursor: String?
            if forceFullRefresh {
                // Q9：cursor 失效时仅清除该 thread 的消息 cursor，从首屏安全重拉。
                await self.repository.deleteMessageSyncCursor(for: threadID)
                cursor = nil
            } else {
                let localCount = await self.repository.countMessages(threadID: threadID)
                if localCount == 0 {
                    cursor = nil
                } else if let persisted = await self.repository.loadMessageSyncCursor(for: threadID)?.value {
                    cursor = persisted
                } else {
                    cursor = await self.repository.latestServerActivity(for: threadID).map(Self.formatSyncCursor)
                }
            }
            try await self.pullAndMerge(cursor: cursor, threadID: threadID)
        }
        inflightSyncTasks[.thread(threadID)] = task
        defer { inflightSyncTasks[.thread(threadID)] = nil }
        try await task.value
        // Q8：定向拉取成功后通知表现层；当前打开的医院会话据此刷新 context/capabilities，
        // 若智能体下架或会话终结则立即切换只读（历史与医生最后消息保持可读）。
        NotificationCenter.default.post(name: .chatRealtimeThreadPullDidComplete, object: threadID)
    }

    /// Q3：账号级全局补偿单轮执行。
    ///
    /// 注册到 `inflightSyncTasks[.global]`，让 thread 级拉取与手动刷新继续互斥；
    /// 但不复用进行中的全局任务——等待其结束后仍执行一轮完整拉取，避免补偿触发被吞。
    private func performGlobalCompensationCycle() async throws {
        while let existing = inflightSyncTasks[.global] {
            try? await existing.value
        }
        let task = Task { () throws -> Void in
            try await self.performManualRefreshSync()
        }
        inflightSyncTasks[.global] = task
        defer { inflightSyncTasks[.global] = nil }
        try await task.value
    }

    /// Q9/Q16.4：实时拉取失败分类。
    static func classifyRealtimePullError(_ error: Error) -> ChatRealtimePullScheduler.PullErrorClassification {
        guard let network = error as? SparkNetworkError else {
            // 非网络层错误：按可重试处理（次数有上限），避免瞬态异常直接放弃。
            return .retryable
        }
        switch network {
        case .transport, .timeout:
            return .retryable
        case .httpError(let statusCode, let backend, _):
            if statusCode >= 500 {
                return .retryable
            }
            if statusCode == 404 {
                return .threadMissing
            }
            if statusCode == 400, let backend {
                if backend.code == 40032 {
                    // invalid_thread_id：该 thread 的自动重试结束。
                    return .threadMissing
                }
                if backend.msg.lowercased().contains("cursor") {
                    // 服务端明确 cursor 无效/过期：仅重置该 thread。
                    return .cursorInvalid
                }
            }
            // 401/403 等：鉴权失效、成员撤权，由既有鉴权/能力流程处理，不重置 cursor、不重试。
            return .terminal
        case .cancelled, .invalidResponse, .decoding, .refreshFailed:
            return .terminal
        }
    }

    private func performGlobalSync() async throws {
        let start = Date()
        logger.debug("聊天同步开始", module: .general)
        try await pushPendingThreadDeletions()
//        try await pushThreads()
        try await pushOutbox()
        let cost = Date().timeIntervalSince(start)
        logger.info("聊天同步完成（仅上送），cost=\(format(cost))s", module: .general)
    }

    private func performManualRefreshSync() async throws {
        let start = Date()
        logger.debug("聊天手动刷新同步开始", module: .general)
        let changedThreads = try await pullThreadDeltas(cursor: await repository.loadThreadSyncCursor()?.value)
        try await pullMessagesForChangedThreads(changedThreads)
        let cost = Date().timeIntervalSince(start)
        logger.info(
            "聊天手动刷新同步完成，changedThreads=\(changedThreads.count), cost=\(format(cost))s",
            module: .general
        )
    }

    private func pushPendingThreadDeletions() async throws {
        try await outboxPipeline.pushPendingThreadDeletions()
    }

    private func pushOutbox() async throws {
        try await outboxPipeline.pushOutbox()
    }

    private func pushThreads() async throws {
        try await outboxPipeline.pushThreads()
    }

    /// 拉线程增量（会话列表），并落本地。
    @discardableResult
    private func pullThreadDeltas(cursor: String?) async throws -> [ChatThread] {
        var allThreads: [ChatThread] = []
        var nextCursor = cursor
        var page = 0

        while true {
            page += 1
            let result = try await remoteAPI.pullThreads(cursor: nextCursor, limit: SyncPaging.threadPageLimit)
            let threads = result.threads.compactMap(ChatSyncEngineDTOMapper.toDomainThread)
            if threads.isEmpty == false {
                await repository.upsertRemoteThreads(threads)
                allThreads.append(contentsOf: threads)
            }
            if let cursor = result.cursor {
                await repository.saveThreadSyncCursor(ChatSyncCursor(value: cursor))
            }

            let canContinue = result.hasMore && page < SyncPaging.maxPagesPerRun
            guard canContinue else { break }
            guard let cursor = result.cursor, cursor != nextCursor else { break }
            nextCursor = cursor
        }

        logger.debug(
            "拉取线程增量完成，threads=\(allThreads.count), pages=\(page), nextCursor=\(nextCursor ?? "-")",
            module: .general
        )
        return allThreads
    }

    private func pullMessagesForChangedThreads(_ threads: [ChatThread]) async throws {
        guard threads.isEmpty == false else { return }

        for thread in threads where thread.isDeleted == false {
            let persistedCursor = await repository.loadMessageSyncCursor(for: thread.id)?.value
            let cursor = if let persistedCursor {
                persistedCursor
            } else {
                await repository.latestServerActivity(for: thread.id).map(Self.formatSyncCursor)
            }
            do {
                try await pullAndMerge(cursor: cursor, threadID: thread.id)
            } catch {
                if isRemoteThreadMissing(error) {
                    continue
                }
                throw error
            }
        }
    }

    private func pullAndMergeAllowingMissingRemoteThread(cursor: String?, threadID: UUID) async throws {
        do {
            try await pullAndMerge(cursor: cursor, threadID: threadID)
        } catch {
            if isRemoteThreadMissing(error) {
                logger.debug(
                    "拉取跳过：服务端尚无该会话，thread=\(shortID(threadID))",
                    module: .general
                )
                return
            }
            throw error
        }
    }

    private func pullAndMerge(cursor: String?, threadID: UUID?) async throws {
        let scope = threadID.map { "thread=\(shortID($0))" } ?? "global"
        logger.debug("CHAT-000061 pull_start cursor=\(cursor == nil ? "nil" : "set") scope=\(scope)", module: .general)

        var nextCursor = cursor
        var page = 0
        var totalMessages = 0
        var touchedThreads: Set<UUID> = []

        while true {
            page += 1
            let result = try await remoteAPI.pull(cursor: nextCursor, threadID: threadID, limit: SyncPaging.messagePageLimit)
            let domainMessages = result.messages.compactMap(ChatSyncEngineDTOMapper.toDomain)
            logger.debug(
                "CHAT-000061 pull_page page=\(page) raw=\(result.messages.count) mapped=\(domainMessages.count) has_more=\(result.hasMore) scope=\(scope)",
                module: .general
            )
            await inboundPipeline.applyRemoteMessages(domainMessages, enqueueAttachmentDownloadJobs: false)
            for tid in Set(domainMessages.map(\.threadID)) {
                touchedThreads.insert(tid)
            }

            totalMessages += result.messages.count
            if let cursor = result.cursor {
                if let threadID {
                    await repository.saveMessageSyncCursor(ChatSyncCursor(value: cursor), for: threadID)
                } else {
                    await repository.saveSyncCursor(ChatSyncCursor(value: cursor))
                }
            }

            let canContinue = result.hasMore && page < SyncPaging.maxPagesPerRun
            guard canContinue else { break }
            guard let cursor = result.cursor, cursor != nextCursor else { break }
            nextCursor = cursor
        }

        logger.debug(
            "拉取对话增量完成，messages=\(totalMessages), threads=\(touchedThreads.count), pages=\(page), nextCursor=\(nextCursor ?? "-")",
            module: .general
        )
    }

    private static func formatSyncCursor(_ date: Date) -> String {
        syncCursorFormatter.string(from: date)
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func needsDoctorSenderBackfill(threadID: UUID) async -> Bool {
        if UserDefaults.standard.bool(forKey: Self.senderBackfillDefaultsKey(threadID)) {
            return false
        }
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        return messages.contains { Self.isDoctorCandidateMissingSender($0) }
    }

    private static func markDoctorSenderBackfillAttempted(threadID: UUID) {
        UserDefaults.standard.set(true, forKey: senderBackfillDefaultsKey(threadID))
    }

    private static func senderBackfillDefaultsKey(_ threadID: UUID) -> String {
        "chat.senderSnapshotBackfill.\(threadID.uuidString)"
    }

    /// 无 modelName 的 assistant 才是真人医生候选；普通 AI 回复都带模型名，不会触发全量回填。
    private static func isDoctorCandidateMissingSender(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant, message.sender == nil else { return false }
        let trimmed = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed == "user"
    }

    private func isRemoteThreadMissing(_ error: Error) -> Bool {
        guard let network = error as? SparkNetworkError else { return false }
        guard case .httpError(let status, let backend, _) = network else { return false }
        guard status == 404, let backend else { return false }
        return backend.code == 40401 || backend.msg == "thread_not_found"
    }

    private func runSingleFlight(
        scope: SyncScope,
        operation: @escaping @Sendable (ChatSyncEngine) async throws -> Void
    ) async throws {
        if case .thread = scope, let globalTask = inflightSyncTasks[.global] {
            logger.debug("同步复用进行中的全局任务", module: .general)
            try await globalTask.value
            return
        }

        if let existing = inflightSyncTasks[scope] {
            logger.debug("同步复用进行中的任务 scope=\(scopeLabel(scope))", module: .general)
            try await existing.value
            return
        }

        let task = Task {
            try await operation(self)
        }
        inflightSyncTasks[scope] = task
        defer { inflightSyncTasks[scope] = nil }
        try await task.value
    }

    private func scopeLabel(_ scope: SyncScope) -> String {
        switch scope {
        case .global:
            return "global"
        case .thread(let id):
            return "thread=\(shortID(id))"
        }
    }
}
