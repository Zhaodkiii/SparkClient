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

    private static let syncCursorFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
            mergeEngine: mergePolicy,
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

    /// 仅上送待同步消息，不拉取（发送成功/重试等路径使用）。
    func pushOutboxOnly() async throws {
        logger.debug("聊天仅上送 outbox", module: .general)
        try await pushPendingThreadDeletions()
//        try await pushThreads()
        try await pushOutbox()
    }

    /// 仅上送指定会话的元数据（单会话变更路径，避免全量推送）。
    func pushSingleThread(threadID: UUID) async throws {
        logger.debug("上送单会话元数据，thread=\(shortID(threadID))", module: .general)
        try await outboxPipeline.pushThread(threadID: threadID)
    }

    /// 打开会话时：仅同步该会话，减少带宽。
    func syncThreadOnOpen(threadID: UUID) async throws {
        try await runSingleFlight(scope: .thread(threadID)) { engine in
            try await engine.performThreadOpenSync(threadID: threadID)
        }
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
        try await pushPendingThreadDeletions()
//        try await pushThreads()
        try await pushOutbox()
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

    private func performThreadOpenSync(threadID: UUID) async throws {
        let start = Date()
        logger.debug("会话打开同步开始，thread=\(shortID(threadID))", module: .general)

        // 本地新建会话：不走后续拉取链路。
        // 仅在本地已有待上送消息时执行上送，避免新建会话触发远端拉取放大。
        if let thread = await repository.loadThread(id: threadID),
           thread.serverUpdatedAt == nil
        {
            let localMessageCount = await repository.countMessages(threadID: threadID)
            if localMessageCount > 0 {
                try await pushPendingThreadDeletions()
//                try await pushThreads()
                try await pushOutbox()
                logger.debug(
                    "会话打开同步完成：本地新建会话仅上送，不执行拉取，thread=\(shortID(threadID))",
                    module: .general
                )
            } else {
                logger.debug(
                    "会话打开同步跳过：本地新建空会话，thread=\(shortID(threadID))",
                    module: .general
                )
            }
            return
        }

        // 存量会话打开：只拉取该会话的未同步消息（thread_id + cursor），不做全局拉取。
        try await pushPendingThreadDeletions()
//        try await pushThreads()
        try await pushOutbox()
        let persistedCursor = await repository.loadMessageSyncCursor(for: threadID)?.value
        let cursor = if let persistedCursor {
            persistedCursor
        } else {
            await repository.latestServerActivity(for: threadID).map(Self.formatSyncCursor)
        }
        try await pullAndMergeAllowingMissingRemoteThread(cursor: cursor, threadID: threadID)
        let cost = Date().timeIntervalSince(start)
        logger.info("会话打开同步完成（单会话增量拉取），cost=\(format(cost))s", module: .general)
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
            await inboundPipeline.applyRemoteMessages(domainMessages, enqueueAttachmentDownloadJobs: true)
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
