import Foundation

struct MemorySyncRunSummary: Sendable {
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
    var pulledEntries: Int = 0
    var pulledTombstones: Int = 0
    var cursorAdvanced: Bool = false
    var result: Outcome = .success

    func logLine() -> String {
        "记忆同步结束 trigger=\(trigger.rawValue) generation=\(generation) result=\(result.rawValue) " +
            "duration_ms=\(durationMs) push_accepted=\(pushAccepted) push_replayed=\(pushReplayed) " +
            "push_retryable_failed=\(pushFailedRetryable) pull_pages=\(pullPages) " +
            "pulled_entries=\(pulledEntries) pulled_tombstones=\(pulledTombstones) cursor_advanced=\(cursorAdvanced)"
    }
}

actor MemorySyncSupervisor {
    private let engine: MemorySyncEngine
    private let logger: Logger
    private nonisolated(unsafe) var localChangeObserver: NSObjectProtocol?
    private var debouncedPushTask: Task<Void, Never>?
    private var currentAccountID: Int64?
    private var currentGeneration: Int64 = 0
    private var lastSuccessfulSyncAt: Date?

    init(engine: MemorySyncEngine, logger: Logger = ConsoleLogger()) {
        self.engine = engine
        self.logger = logger
        let observer = NotificationCenter.default.addObserver(
            forName: .sparkMemoryLocalMutationDidHappen,
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

    func startForAccount(accountID: Int64) {
        currentAccountID = accountID
        currentGeneration += 1
    }

    func cancelForAccountSwitch() {
        currentAccountID = nil
        currentGeneration += 1
        debouncedPushTask?.cancel()
        debouncedPushTask = nil
    }

    func scheduleStartupSync(accountID: Int64) {
        guard accountID == currentAccountID else { return }
        runTriggeredSync(trigger: .startup, accountID: accountID, generation: currentGeneration)
    }

    func scheduleLoginSync(accountID: Int64) {
        guard accountID == currentAccountID else { return }
        runTriggeredSync(trigger: .login, accountID: accountID, generation: currentGeneration)
    }

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

    @discardableResult
    func manualRefresh() async -> MemorySyncRunSummary {
        guard let accountID = currentAccountID else {
            return MemorySyncRunSummary(trigger: .manual, generation: currentGeneration, startedAt: Date(), result: .skippedOffline)
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

    private func runTriggeredSync(trigger: MemorySyncRunSummary.Trigger, accountID: Int64, generation: Int64) {
        Task { [weak self] in
            await self?.performSync(trigger: trigger, accountID: accountID, generation: generation)
        }
    }

    @discardableResult
    private func performSync(trigger: MemorySyncRunSummary.Trigger, accountID: Int64, generation: Int64) async -> MemorySyncRunSummary {
        let startedAt = Date()
        guard generation == currentGeneration, accountID == currentAccountID else {
            return MemorySyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt, result: .cancelledAccountSwitch)
        }

        let result = await engine.syncNowWithPull()
        guard generation == currentGeneration else {
            return MemorySyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt, result: .cancelledAccountSwitch)
        }

        var summary = MemorySyncRunSummary(trigger: trigger, generation: generation, startedAt: startedAt)
        summary.pushAccepted = result.push.accepted
        summary.pushReplayed = result.push.replayed
        summary.pushFailedRetryable = result.push.failedRetryable
        summary.pushFailedPermanent = result.push.failedPermanent
        summary.conflictsResolvedByServer = result.push.conflictsResolvedByServer
        summary.pullPages = result.pull.pages
        summary.pulledEntries = result.pull.pulledEntries
        summary.pulledTombstones = result.pull.pulledTombstones
        summary.cursorAdvanced = result.pull.cursorAdvanced
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
        await logger.info(summary.logLine(), module: .general)
        return summary
    }
}
