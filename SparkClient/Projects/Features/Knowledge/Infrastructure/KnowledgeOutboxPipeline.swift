import Foundation

/// Push 主流程：取待发 Outbox → 冻结 payload 构建请求 → 调用远端 API → 按逐条 ACK 结果收敛本地状态。
/// 单条冲突/失败不阻断同批其它 mutation（工单 5.3/5.5）。
struct KnowledgeOutboxPipeline: Sendable {
    private let outboxStore: KnowledgeSyncOutboxStore
    private let remoteAPI: SparkKnowledgeRemoteAPI
    private let logger: Logger

    nonisolated init(outboxStore: KnowledgeSyncOutboxStore, remoteAPI: SparkKnowledgeRemoteAPI, logger: Logger = ConsoleLogger()) {
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.logger = logger
    }

    /// 推送一批（默认最多 50 条，对齐服务端批次上限）；返回处理的 mutation 数，供 SyncRunSummary 统计。
    @discardableResult
    func pushPendingBatch(limit: Int = 50) async -> KnowledgeOutboxPushSummary {
        let pending = await outboxStore.pending(limit: limit)
        guard pending.isEmpty == false else {
            return KnowledgeOutboxPushSummary()
        }

        await outboxStore.markSending(mutationIDs: pending.map(\.mutationID))

        let requests = pending.map { record in
            KnowledgeSyncDTOMapper.mutationRequest(
                record: record,
                payload: KnowledgeOutboxPayload.decode(record.payload),
                clientPlatform: KnowledgeClientMetadata.platform,
                clientVersion: KnowledgeClientMetadata.appVersion,
                deviceID: KnowledgeClientMetadata.deviceID
            )
        }

        var summary = KnowledgeOutboxPushSummary()
        do {
            let result = try await remoteAPI.push(mutations: requests)
            let acksByMutationID = Dictionary(uniqueKeysWithValues: result.acks.map { ($0.mutationId, $0) })
            for record in pending {
                guard let ack = acksByMutationID[record.mutationID] else {
                    // 服务端未对该 mutation 返回结果（异常响应）：按可重试失败处理，等待下一轮。
                    await fail(record, errorCode: "knowledge_push_ack_missing", retryable: true)
                    summary.failedRetryable += 1
                    continue
                }
                await apply(ack: ack, for: record, into: &summary)
            }
        } catch {
            // 整批网络失败（超时/断网）：全部标记可重试，等待下一轮统一重试，不阻断 Pull。
            for record in pending {
                await fail(record, errorCode: "knowledge_push_network_error", retryable: true)
            }
            summary.failedRetryable += pending.count
            logger.warning("知识同步 Push 网络失败 count=\(pending.count) error=\(error.localizedDescription)", module: .general)
        }
        return summary
    }

    private func apply(ack: KnowledgePushAckDTO, for record: KnowledgeOutboxRecord, into summary: inout KnowledgeOutboxPushSummary) async {
        switch ack.status {
        case "accepted":
            summary.accepted += 1
            if ack.replayed == true { summary.replayed += 1 }
            guard let revision = ack.revision, let serverUpdatedAt = ack.serverUpdatedAt else {
                await fail(record, errorCode: "knowledge_push_ack_invalid", retryable: true)
                return
            }
            await outboxStore.markAccepted(
                mutationID: record.mutationID,
                documentID: record.documentID,
                revision: revision,
                serverUpdatedAt: serverUpdatedAt,
                contentHash: ack.contentHash ?? ""
            )
        case "conflict":
            summary.conflictsResolvedByServer += 1
            guard let currentDocument = ack.currentDocument else {
                await fail(record, errorCode: ack.code ?? "knowledge_conflict_missing_snapshot", retryable: false)
                return
            }
            await outboxStore.resolveByServer(
                mutationID: record.mutationID,
                snapshot: KnowledgeSyncDTOMapper.remoteSnapshot(from: currentDocument)
            )
        default:
            let code = ack.code ?? "knowledge_push_unknown_error"
            let retryable = Self.retryableErrorCodes.contains(code)
            await fail(record, errorCode: code, retryable: retryable)
            if retryable { summary.failedRetryable += 1 } else { summary.failedPermanent += 1 }
        }
    }

    private func fail(_ record: KnowledgeOutboxRecord, errorCode: String, retryable: Bool) async {
        if retryable, Int(record.attemptCount) + 1 < KnowledgeRetryPolicy.maxAttempts {
            let delay = KnowledgeRetryPolicy.nextAttemptDelay(attemptCount: record.attemptCount)
            await outboxStore.markFailedRetryable(
                mutationID: record.mutationID,
                errorCode: errorCode,
                nextAttemptAt: Date().addingTimeInterval(delay)
            )
        } else {
            await outboxStore.markFailedPermanent(mutationID: record.mutationID, errorCode: errorCode)
        }
    }

    /// 可重试的业务错误码：网络/限流/暂时不可用；其余 4xx 视为契约错误，标记永久失败。
    private static let retryableErrorCodes: Set<String> = [
        "knowledge_rate_limited",
        "knowledge_index_unavailable",
        "knowledge_push_network_error",
        "knowledge_push_ack_missing",
        "knowledge_push_ack_invalid",
    ]
}

struct KnowledgeOutboxPushSummary: Sendable {
    var accepted: Int = 0
    var replayed: Int = 0
    var conflictsResolvedByServer: Int = 0
    var failedRetryable: Int = 0
    var failedPermanent: Int = 0
}

/// 请求元数据：仅用于诊断来源，不作为知识归属或去重主键（工单 5.1.3）。
enum KnowledgeClientMetadata {
    static let platform = "ios"
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    static var deviceID: String {
        SparkKeychain.getOrCreateDeviceID()
    }
}
