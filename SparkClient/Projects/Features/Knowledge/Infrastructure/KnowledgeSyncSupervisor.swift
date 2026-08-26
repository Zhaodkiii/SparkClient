import Foundation

/// 一轮同步的脱敏结果摘要；日志只记录统计，不含正文/向量/Token（工单 11.7）。
struct KnowledgeSyncRunSummary: Sendable {
    enum Trigger: String, Sendable {
        case startup, login, foreground, networkRecovered, manual, localMutation
    }

    enum Outcome: String, Sendable {
        case success, partialFailure, failed, skippedOffline, cancelledAccountSwitch
    }

    let trigger: Trigger
    let generation: Int64
    let startedAt: Date
    var durationMs: Int = 0
    var pushAccepted: Int = 0
    var pushReplayed: Int = 0
    var pushFailedRetryable: Int = 0
    var pushFailedPermanent: Int = 0
    var conflictsResolvedByServer: Int = 0
    var pullPages: Int = 0
    var pulledDocuments: Int = 0
    var pulledTombstones: Int = 0
    var cursorAdvanced: Bool = false
    var embeddingRebuildScheduled: Int = 0
    var result: Outcome = .success

    func logLine() -> String {
        "知识同步结束 trigger=\(trigger.rawValue) generation=\(generation) result=\(result.rawValue) " +
            "duration_ms=\(durationMs) push_accepted=\(pushAccepted) push_replayed=\(pushReplayed) " +
            "push_retryable_failed=\(pushFailedRetryable) push_permanent_failed=\(pushFailedPermanent) " +
            "conflicts_resolved=\(conflictsResolvedByServer) pull_pages=\(pullPages) " +
            "pulled_documents=\(pulledDocuments) pulled_tombstones=\(pulledTombstones) " +
            "cursor_advanced=\(cursorAdvanced) embedding_rebuild_scheduled=\(embeddingRebuildScheduled)"
    }
}

/// 编排知识同步子系统：创建后防抖 Push、启动/登录/前台/网络恢复/手动触发的非阻断入口。
/// 所有公开触发方法立即返回或在内部 Task 中运行，绝不阻塞调用方（工单 5.8、6.5）。
actor KnowledgeSyncSupervisor {
    private let engine: KnowledgeSyncEngine
    private let rebuildChunkEmbeddings: @Sendable (UUID) async -> Void
    private let logger: Logger

    private nonisolated(unsafe) var localChangeObserver: NSObjectProtocol?
    private var debouncedPushTask: Task<Void, Never>?
    private var currentAccountID: Int64?
    private var currentGeneration: Int64 = 0
    private var lastSuccessfulSyncAt: Date?

    init(
        engine: KnowledgeSyncEngine,
        rebuildChunkEmbeddings: @escaping @Sendable (UUID) async -> Void,
        logger: Logger = ConsoleLogger()
    ) {
        self.engine = engine
        self.rebuildChunkEmbeddings = rebuildChunkEmbeddings
        self.logger = logger
        let observer = NotificationCenter.default.addObserver(
            forName: .sparkKnowledgeDatabaseDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.scheduleDebouncedPush() }
        }
        self.localChangeObserver = observer
    }

    deinit {
        if let localChangeObserver {
            NotificationCenter.default.removeObserver(localChangeObserver)
        }
        debouncedPushTask?.cancel()
    }

    // MARK: - 账号运行时门禁

    /// 账号激活/切换后调用；只更新当前 generation，不在此处发起网络请求。
    func startForAccount(accountID: Int64) {
        currentAccountID = accountID
        currentGeneration += 1
    }

    /// 账号切换/退出时调用：使旧 generation 的迟到回调全部失效。
    func cancelForAccountSwitch() {
        currentAccountID = nil
        currentGeneration += 1
        debouncedPushTask?.cancel()
        debouncedPushTask = nil
    }

    // MARK: - 触发入口（全部非阻断：立即返回，内部异步执行）

    /// 应用启动完成账号恢复后调用；必须立即返回，不显示全屏等待态。
    /// `generation` 由内部维护（`startForAccount` 递增），调用方无需感知，避免跨层传递计数器。
    func scheduleStartupSync(accountID: Int64) {
        guard accountID == currentAccountID else { return }
        runTriggeredSync(trigger: .startup, accountID: accountID, generation: currentGeneration)
    }

    func scheduleLoginSync(accountID: Int64) {
        guard accountID == currentAccountID else { return }
        runTriggeredSync(trigger: .login, accountID: accountID, generation: currentGeneration)
    }

    /// 回前台：距上次成功同步超过 30 秒或存在待发 Outbox 时才同步，避免频繁抖动。
    func scheduleForegroundSyncIfNeeded() {
        guard let accountID = currentAccountID else { return }
        if let last = lastSuccessfulSyncAt, Date().timeIntervalSince(last) < 30 {
            return
        }
        runTriggeredSync(trigger: .foreground, accountID: accountID, generation: currentGeneration)
    }

    func scheduleNetworkRecoveredSync() {
        guard let accountID = currentAccountID else { return }
        runTriggeredSync(trigger: .networkRecovered, accountID: accountID, generation: currentGeneration)
    }

    /// 手动下拉刷新：向用户返回最终结果，因此调用方可以 `await` 本方法。
    @discardableResult
    func manualRefresh() async -> KnowledgeSyncRunSummary {
        guard let accountID = currentAccountID else {
            return KnowledgeSyncRunSummary(trigger: .manual, generation: currentGeneration, startedAt: Date(), result: .skippedOffline)
        }
        return await performSync(trigger: .manual, accountID: accountID, generation: currentGeneration)
    }

    private func scheduleDebouncedPush() {
        guard let accountID = currentAccountID else { return }
        let generation = currentGeneration
        debouncedPushTask?.cancel()
        debouncedPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard Task.isCancelled == false, let self else { return }
            _ = await self.performSync(trigger: .localMutation, accountID: accountID, generation: generation)
        }
    }

    private func runTriggeredSync(trigger: KnowledgeSyncRunSummary.Trigger, accountID: Int64, generation: Int64) {
        Task { [weak self] in
            await self?.performSync(trigger: trigger, accountID: accountID, generation: generation)
        }
    }

    @discardableResult
    private func performSync(trigger: KnowledgeSyncRunSummary.Trigger, accountID: Int64, generation: Int64) async -> KnowledgeSyncRunSummary {
        let startedAt = Date()
        guard generation == currentGeneration, accountID == currentAccountID else {
            return KnowledgeSyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt, result: .cancelledAccountSwitch)
        }

        let result = await engine.syncNowWithPull()

        // 结果落地前再次校验 generation：账号切换后旧 generation 的迟到结果一律丢弃，不写入新账号存储。
        guard generation == currentGeneration else {
            return KnowledgeSyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt, result: .cancelledAccountSwitch)
        }

        var summary = KnowledgeSyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt)
        summary.pushAccepted = result.push.accepted
        summary.pushReplayed = result.push.replayed
        summary.pushFailedRetryable = result.push.failedRetryable
        summary.pushFailedPermanent = result.push.failedPermanent
        summary.conflictsResolvedByServer = result.push.conflictsResolvedByServer
        summary.pullPages = result.pull.pages
        summary.pulledDocuments = result.pull.pulledDocuments
        summary.pulledTombstones = result.pull.pulledTombstones
        summary.cursorAdvanced = result.pull.cursorAdvanced
        summary.embeddingRebuildScheduled = result.pull.changedContentDocumentIDs.count
        summary.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        if result.pull.failed && result.push.failedRetryable > 0 {
            summary.result = .failed
        } else if result.pull.failed || result.push.failedRetryable > 0 || result.push.failedPermanent > 0 {
            summary.result = .partialFailure
        } else {
            summary.result = .success
        }

        if summary.result == .success || summary.result == .partialFailure {
            lastSuccessfulSyncAt = Date()
        }

        for documentID in result.pull.changedContentDocumentIDs {
            let capturedGeneration = generation
            Task { [weak self] in
                guard let self else { return }
                guard await self.isGenerationStillValid(capturedGeneration) else { return }
                await self.rebuildChunkEmbeddings(documentID)
            }
        }

        await logger.info(summary.logLine(), module: .general)
        return summary
    }

    private func isGenerationStillValid(_ generation: Int64) -> Bool {
        generation == currentGeneration
    }
}
