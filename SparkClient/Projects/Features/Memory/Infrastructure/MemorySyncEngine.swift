import Foundation

actor MemorySyncEngine {
    private enum Paging {
        static let pullPageLimit = 100
        static let maxPagesPerRun = 20
    }

    private let repository: any MemoryEntityRepository
    private let outboxStore: MemorySyncOutboxStore
    private let outboxPipeline: MemoryOutboxPipeline
    private let remoteAPI: SparkMemoryRemoteAPI
    private let logger: Logger
    private var inflightTask: Task<MemorySyncRunResult, Never>?

    init(
        repository: any MemoryEntityRepository,
        outboxStore: MemorySyncOutboxStore,
        remoteAPI: SparkMemoryRemoteAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.outboxPipeline = MemoryOutboxPipeline(outboxStore: outboxStore, remoteAPI: remoteAPI, logger: logger)
        self.logger = logger
    }

    @discardableResult
    func syncNowWithPull() async -> MemorySyncRunResult {
        await runSingleFlight { engine in
            var result = MemorySyncRunResult()
            await engine.outboxStore.recoverSendingToPending()
            result.pull = await engine.pullAllPages()
            await engine.outboxStore.discardCovered()
            result.push = await engine.outboxPipeline.pushPendingBatch()
            let converge = await engine.pullAllPages()
            result.pull.pages += converge.pages
            result.pull.pulledEntries += converge.pulledEntries
            result.pull.pulledTombstones += converge.pulledTombstones
            result.pull.cursorAdvanced = result.pull.cursorAdvanced || converge.cursorAdvanced
            result.pull.failed = result.pull.failed || converge.failed
            return result
        }
    }

    private func pullAllPages() async -> MemorySyncPullSummary {
        var summary = MemorySyncPullSummary()
        var cursor = await repository.loadSyncCursor()
        await repository.markPullStarted()
        var page = 0

        while page < Paging.maxPagesPerRun {
            page += 1
            let result: MemoryRemotePullResult
            do {
                result = try await remoteAPI.pull(cursor: cursor, limit: Paging.pullPageLimit)
            } catch {
                summary.failed = true
                await repository.saveSyncCursor(cursor, pullSucceeded: false, errorCode: "memory_pull_network_error")
                logger.warning("记忆同步 Pull 失败 page=\(page) error=\(error.localizedDescription)", module: .general)
                break
            }

            await repository.applyRemoteSnapshots(result.items.map { MemorySyncDTOMapper.remoteSnapshot(from: $0) })
            summary.pulledEntries += result.items.count
            summary.pulledTombstones += result.items.filter(\.isDeleted).count
            summary.pages += 1
            if result.cursor == cursor, result.items.isEmpty == false, result.hasMore {
                logger.warning("记忆同步 Pull 返回未推进的 cursor，停止本轮分页", module: .general)
                break
            }
            await repository.saveSyncCursor(result.cursor, pullSucceeded: true, errorCode: nil)
            summary.cursorAdvanced = true
            cursor = result.cursor
            if result.hasMore == false || result.items.isEmpty {
                break
            }
        }
        return summary
    }

    private func runSingleFlight(
        _ operation: @escaping @Sendable (MemorySyncEngine) async -> MemorySyncRunResult
    ) async -> MemorySyncRunResult {
        if let existing = inflightTask {
            return await existing.value
        }
        let task = Task { await operation(self) }
        inflightTask = task
        defer { inflightTask = nil }
        return await task.value
    }
}

struct MemorySyncPullSummary: Sendable {
    var pages: Int = 0
    var pulledEntries: Int = 0
    var pulledTombstones: Int = 0
    var cursorAdvanced: Bool = false
    var failed: Bool = false
}

struct MemorySyncRunResult: Sendable {
    var push: MemoryOutboxPushSummary = MemoryOutboxPushSummary()
    var pull: MemorySyncPullSummary = MemorySyncPullSummary()
}
