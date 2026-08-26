import Foundation

/// 知识同步引擎：账号级 single-flight，Push/Pull 分阶段失败隔离（工单 5.8/5.7）。
/// 独立于 `ChatSyncEngine`：不共用表、不共用 cursor、不共用 Outbox。
actor KnowledgeSyncEngine {
    private enum Paging {
        static let pullPageLimit = 100
        static let maxPagesPerRun = 20
    }

    private let repository: any KnowledgeRepository
    private let outboxPipeline: KnowledgeOutboxPipeline
    private let inboundPipeline: KnowledgeInboundPipeline
    private let remoteAPI: SparkKnowledgeRemoteAPI
    private let logger: Logger

    private var inflightTask: Task<KnowledgeSyncRunResult, Never>?

    init(
        repository: any KnowledgeRepository,
        outboxStore: KnowledgeSyncOutboxStore,
        remoteAPI: SparkKnowledgeRemoteAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.remoteAPI = remoteAPI
        self.outboxPipeline = KnowledgeOutboxPipeline(outboxStore: outboxStore, remoteAPI: remoteAPI, logger: logger)
        self.inboundPipeline = KnowledgeInboundPipeline(repository: repository)
        self.logger = logger
    }

    /// 仅 Push；Pull 失败不影响本方法（本方法根本不 Pull）。
    @discardableResult
    func syncNow() async -> KnowledgeSyncRunResult {
        await runSingleFlight { engine in
            var result = KnowledgeSyncRunResult()
            result.push = await engine.outboxPipeline.pushPendingBatch()
            return result
        }
    }

    /// Push 全部处理完（无论成败）后继续 Pull，直至无更多页或达到单轮页数上限。
    @discardableResult
    func syncNowWithPull() async -> KnowledgeSyncRunResult {
        await runSingleFlight { engine in
            var result = KnowledgeSyncRunResult()
            result.push = await engine.outboxPipeline.pushPendingBatch()
            result.pull = await engine.pullAllPages()
            return result
        }
    }

    /// 仅增量 Pull（例如手动下拉刷新已确认 Outbox 为空时）。
    @discardableResult
    func pullIncremental() async -> KnowledgeSyncRunResult {
        await runSingleFlight { engine in
            var result = KnowledgeSyncRunResult()
            result.pull = await engine.pullAllPages()
            return result
        }
    }

    private func pullAllPages() async -> KnowledgeSyncPullSummary {
        var summary = KnowledgeSyncPullSummary()
        var cursor = await repository.loadSyncCursor()
        var page = 0

        while page < Paging.maxPagesPerRun {
            page += 1
            let result: KnowledgeRemotePullResult
            do {
                result = try await remoteAPI.pull(cursor: cursor, limit: Paging.pullPageLimit)
            } catch {
                // Pull 失败：cursor 不推进，不影响已完成的 Push ACK；下一轮从旧 cursor 重拉。
                summary.failed = true
                logger.warning("知识同步 Pull 失败 page=\(page) error=\(error.localizedDescription)", module: .general)
                break
            }

            let changedIDs = await inboundPipeline.applyRemotePage(result.documents)
            summary.pulledDocuments += result.documents.count
            summary.pulledTombstones += result.documents.filter(\.isDeleted).count
            summary.changedContentDocumentIDs.append(contentsOf: changedIDs)
            summary.pages += 1

            // 本页整体落地成功（applyRemotePage 已在同一 Core Data 事务内完成）后才推进 cursor。
            await repository.saveSyncCursor(result.cursor)
            summary.cursorAdvanced = true
            cursor = result.cursor

            if result.hasMore == false {
                break
            }
        }
        return summary
    }

    private func runSingleFlight(
        _ operation: @escaping @Sendable (KnowledgeSyncEngine) async -> KnowledgeSyncRunResult
    ) async -> KnowledgeSyncRunResult {
        if let existing = inflightTask {
            return await existing.value
        }
        let task = Task { await operation(self) }
        inflightTask = task
        defer { inflightTask = nil }
        return await task.value
    }
}

struct KnowledgeSyncPullSummary: Sendable {
    var pages: Int = 0
    var pulledDocuments: Int = 0
    var pulledTombstones: Int = 0
    var changedContentDocumentIDs: [UUID] = []
    var cursorAdvanced: Bool = false
    var failed: Bool = false
}

struct KnowledgeSyncRunResult: Sendable {
    var push: KnowledgeOutboxPushSummary = KnowledgeOutboxPushSummary()
    var pull: KnowledgeSyncPullSummary = KnowledgeSyncPullSummary()
}
