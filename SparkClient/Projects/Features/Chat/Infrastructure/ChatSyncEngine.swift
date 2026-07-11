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

    /// 进入会话：只拉取当前会话的消息增量。
    /// 若本地已有消息，从本地已知最新远端活动之后拉；若本地为空，则 cursor=nil 拉首屏远端消息。
    func pullThreadMessagesIncrementalOnOpen(threadID: UUID) async throws {
        try await runSingleFlight(scope: .thread(threadID)) { engine in
            let localCount = await engine.repository.countMessages(threadID: threadID)
            let cursor: String?
            if localCount == 0 {
                cursor = nil
            } else if let persisted = await engine.repository.loadMessageSyncCursor(for: threadID)?.value {
                cursor = persisted
            } else {
                cursor = await engine.repository.latestServerActivity(for: threadID).map(Self.formatSyncCursor)
            }
            try await engine.pullAndMergeAllowingMissingRemoteThread(cursor: cursor, threadID: threadID)
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
        await realtimeClient.start { [weak self] hintCursor in
            guard let self else { return }
            Task {
                do {
                    try await self.runSingleFlight(scope: .global) { engine in
                        try await engine.performRealtimeHintSync(cursor: hintCursor)
                    }
                } catch {
                    self.logger.warning("chat realtime sync failed: \(error.localizedDescription)", module: .general)
                }
            }
        }
    }

    func stopRealtimeSync() async {
        await realtimeClient?.stop()
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

    private func performRealtimeHintSync(cursor: String?) async throws {
        _ = cursor
        // 按当前策略：realtime 后续拉取链路已移除，仅保留本地待同步数据上送。
        try await pushPendingThreadDeletions()
//        try await pushThreads()
        try await pushOutbox()
        logger.debug("realtime 提示处理完成：仅上送，不执行拉取", module: .general)
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
        logger.debug("拉取对话增量开始，cursor=\(cursor ?? "-") scope=\(scope)", module: .general)

        var nextCursor = cursor
        var page = 0
        var totalMessages = 0
        var touchedThreads: Set<UUID> = []

        while true {
            page += 1
            let result = try await remoteAPI.pull(cursor: nextCursor, threadID: threadID, limit: SyncPaging.messagePageLimit)
            let domainMessages = result.messages.compactMap(ChatSyncEngineDTOMapper.toDomain)
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
