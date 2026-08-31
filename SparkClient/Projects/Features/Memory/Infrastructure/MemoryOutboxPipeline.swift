import Foundation

struct MemoryOutboxPipeline: Sendable {
    private let outboxStore: MemorySyncOutboxStore
    private let remoteAPI: SparkMemoryRemoteAPI
    private let logger: Logger

    nonisolated init(outboxStore: MemorySyncOutboxStore, remoteAPI: SparkMemoryRemoteAPI, logger: Logger = ConsoleLogger()) {
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.logger = logger
    }

    @discardableResult
    func pushPendingBatch(limit: Int = 50) async -> MemoryOutboxPushSummary {
        let pending = await outboxStore.pending(limit: limit)
        guard pending.isEmpty == false else {
            return MemoryOutboxPushSummary()
        }

        await outboxStore.markSending(mutationIDs: pending.map(\.mutationID))
        let requests = pending.map { record in
            MemorySyncDTOMapper.mutationRequest(
                record: record,
                payload: MemoryOutboxPayload.decode(record.payload),
                clientPlatform: MemoryClientMetadata.platform,
                clientVersion: MemoryClientMetadata.appVersion,
                deviceID: MemoryClientMetadata.deviceID
            )
        }

        var summary = MemoryOutboxPushSummary()
        do {
            let result = try await remoteAPI.push(mutations: requests)
            let acksByID = Dictionary(uniqueKeysWithValues: result.acks.map { ($0.mutationId, $0) })
            for record in pending {
                guard let ack = acksByID[record.mutationID] else {
                    await fail(record, errorCode: "memory_push_ack_missing", retryable: true)
                    summary.failedRetryable += 1
                    continue
                }
                await apply(ack: ack, for: record, into: &summary)
            }
        } catch {
            for record in pending {
                await fail(record, errorCode: "memory_push_network_error", retryable: true)
            }
            summary.failedRetryable += pending.count
            logger.warning("记忆同步 Push 网络失败 count=\(pending.count) error=\(error.localizedDescription)", module: .general)
        }
        return summary
    }

    private func apply(ack: MemoryPushAckDTO, for record: MemoryOutboxRecord, into summary: inout MemoryOutboxPushSummary) async {
        switch ack.status {
        case "accepted", "replayed":
            summary.accepted += 1
            if ack.replayed == true { summary.replayed += 1 }
            guard let snapshotDTO = ack.snapshot else {
                await fail(record, errorCode: "memory_push_ack_invalid", retryable: true)
                return
            }
            await outboxStore.markAccepted(mutationID: record.mutationID, snapshot: MemorySyncDTOMapper.remoteSnapshot(from: snapshotDTO))
        case "conflict":
            summary.conflictsResolvedByServer += 1
            guard let snapshotDTO = ack.snapshot else {
                await fail(record, errorCode: ack.reasonCode ?? "memory_conflict_missing_snapshot", retryable: false)
                return
            }
            await outboxStore.resolveByServer(
                mutationID: record.mutationID,
                snapshot: MemorySyncDTOMapper.remoteSnapshot(from: snapshotDTO)
            )
        default:
            let code = ack.reasonCode ?? "memory_push_unknown_error"
            let retryable = Self.retryableErrorCodes.contains(code)
            await fail(record, errorCode: code, retryable: retryable)
            if retryable { summary.failedRetryable += 1 } else { summary.failedPermanent += 1 }
        }
    }

    private func fail(_ record: MemoryOutboxRecord, errorCode: String, retryable: Bool) async {
        if retryable, Int(record.attemptCount) + 1 < MemoryRetryPolicy.maxAttempts {
            let delay = MemoryRetryPolicy.nextAttemptDelay(attemptCount: record.attemptCount)
            await outboxStore.markFailedRetryable(
                mutationID: record.mutationID,
                errorCode: errorCode,
                nextRetryAt: Date().addingTimeInterval(delay)
            )
        } else {
            await outboxStore.markFailedPermanent(mutationID: record.mutationID, errorCode: errorCode)
        }
    }

    private static let retryableErrorCodes: Set<String> = [
        "memory_push_network_error",
        "memory_push_ack_missing",
        "memory_push_ack_invalid",
        "memory_unavailable",
        "memory_rate_limited",
    ]
}

struct MemoryOutboxPushSummary: Sendable {
    var accepted: Int = 0
    var replayed: Int = 0
    var conflictsResolvedByServer: Int = 0
    var failedRetryable: Int = 0
    var failedPermanent: Int = 0
}

enum MemoryClientMetadata {
    static let platform = "ios"
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    static var deviceID: String {
        SparkKeychain.getOrCreateDeviceID()
    }
}
