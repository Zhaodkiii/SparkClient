import Foundation

actor MemorySyncOutboxStore {
    private let repository: any MemoryEntityRepository

    init(repository: any MemoryEntityRepository) {
        self.repository = repository
    }

    func pending(limit: Int = 50) async -> [MemoryOutboxRecord] {
        await repository.loadPendingOutbox(limit: limit)
    }

    func recoverSendingToPending() async {
        await repository.recoverSendingOutboxToPending()
    }

    func discardCovered() async {
        await repository.discardOutboxCoveredByHigherRevision()
    }

    func markSending(mutationIDs: [UUID]) async {
        await repository.markOutboxSending(mutationIDs: mutationIDs)
    }

    func markAccepted(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {
        await repository.markOutboxAccepted(mutationID: mutationID, snapshot: snapshot)
    }

    func resolveByServer(mutationID: UUID, snapshot: MemoryRemoteSnapshot) async {
        await repository.resolveConflictWithServerSnapshot(mutationID: mutationID, snapshot: snapshot)
    }

    func markFailedRetryable(mutationID: UUID, errorCode: String, nextRetryAt: Date) async {
        await repository.markOutboxFailedRetryable(mutationID: mutationID, errorCode: errorCode, nextRetryAt: nextRetryAt)
    }

    func markFailedPermanent(mutationID: UUID, errorCode: String) async {
        await repository.markOutboxFailedPermanent(mutationID: mutationID, errorCode: errorCode)
    }
}

enum MemoryRetryPolicy {
    static let maxAttempts = 8

    static func nextAttemptDelay(attemptCount: Int32) -> TimeInterval {
        let exponent = max(0, Int(attemptCount))
        let base = min(15 * 60, pow(2.0, Double(exponent)) * 5)
        let jitter = base * Double.random(in: 0...0.25)
        return base + jitter
    }
}
