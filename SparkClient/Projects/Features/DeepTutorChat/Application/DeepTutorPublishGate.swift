import Foundation

enum DeepTutorPublishPriority: Sendable {
    case immediate
    case normal
    case reasoningCoalesce
}

@MainActor
protocol DeepTutorMessageListRenderStateObserving: AnyObject {
    func messageListWillApplySnapshot(conversationID: UUID)
    func messageListDidApplySnapshot(conversationID: UUID, durationMs: Int)
}

@MainActor
final class DeepTutorPublishGate {
    var isMessageListApplying = false

    private var pendingCommits: [() -> Void] = []
    private var scheduled = false
    private var reasoningCoalesceTask: Task<Void, Never>?

    func deferPublish(source: String, priority: DeepTutorPublishPriority = .normal, _ commit: @escaping () -> Void) {
        if isMessageListApplying {
            DeepTutorChatLog.publishGuardBlocked(mutation: "state", reason: "snapshot_applying", source: source)
            pendingCommits.append(commit)
            return
        }
        enqueue(commit, source: source, priority: priority)
    }

    func enqueue(_ commit: @escaping () -> Void, source: String, priority: DeepTutorPublishPriority) {
        pendingCommits.append(commit)
        scheduleFlush(source: source, priority: priority)
    }

    func flushAfterSnapshotApply() {
        guard isMessageListApplying == false else { return }
        scheduleFlush(source: "snapshot_apply_completion", priority: .normal)
    }

    private func scheduleFlush(source: String, priority: DeepTutorPublishPriority) {
        switch priority {
        case .immediate:
            reasoningCoalesceTask?.cancel()
            scheduleNextTurn(source: source, delayMs: 0)
        case .normal:
            scheduleNextTurn(source: source, delayMs: 0)
        case .reasoningCoalesce:
            reasoningCoalesceTask?.cancel()
            reasoningCoalesceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                scheduleNextTurn(source: source, delayMs: 0)
            }
        }
    }

    private func scheduleNextTurn(source: String, delayMs: Int) {
        guard scheduled == false else { return }
        scheduled = true
        Task { @MainActor in
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(delayMs))
            } else {
                await Task.yield()
            }
            scheduled = false
            if isMessageListApplying {
                DeepTutorChatLog.publishGuardBlocked(mutation: "state", reason: "view_update", source: source)
                scheduleNextTurn(source: source, delayMs: 0)
                return
            }
            flushPendingCommits(source: source)
        }
    }

    private func flushPendingCommits(source: String) {
        guard pendingCommits.isEmpty == false else { return }
        let start = Date()
        let commits = pendingCommits
        pendingCommits = []
        for commit in commits {
            commit()
        }
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        DeepTutorChatLog.publishCommit(source: source, mutationCount: commits.count, durationMs: durationMs)
    }
}
