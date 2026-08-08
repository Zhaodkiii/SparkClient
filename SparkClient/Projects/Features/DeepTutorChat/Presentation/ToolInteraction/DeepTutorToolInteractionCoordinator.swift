import Combine
import Foundation

@MainActor
final class DeepTutorToolInteractionCoordinator: ObservableObject {
    struct ActivePresentation: Identifiable, Equatable {
        let id: UUID
        let snapshot: DeepTutorToolInteractionSnapshot
    }

    @Published private(set) var activePresentation: ActivePresentation?

    private struct QueuedWork {
        let id: UUID
        let snapshot: DeepTutorToolInteractionSnapshot
    }

    private enum PendingOutcome {
        case toolPreviewDismissed
    }

    private var queue: [QueuedWork] = []
    private var isDraining = false
    private var userWaitGate: CheckedContinuation<Void, Never>?
    private var pendingOutcome: PendingOutcome?

    var queueCount: Int { queue.count }
    var isPresenting: Bool { activePresentation != nil }
    var isQueueDraining: Bool { isDraining }

    func presentToolPreview(prompt: DeepTutorToolPreviewPrompt) {
        enqueue(
            QueuedWork(
                id: prompt.id,
                snapshot: .toolPreview(prompt)
            )
        )
    }

    func dismissToolPreview(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .toolPreview = activePresentation?.snapshot else { return }
        pendingOutcome = .toolPreviewDismissed
        activePresentation = nil
        resumeUserGate()
    }

    func dismissActivePresentationByUser() {
        guard let active = activePresentation, pendingOutcome == nil else { return }
        switch active.snapshot {
        case .toolPreview:
            dismissToolPreview(id: active.id)
        }
    }

    func reset() {
        queue.removeAll()
        pendingOutcome = nil
        activePresentation = nil
        resumeUserGate()
    }

    private func enqueue(_ work: QueuedWork) {
        queue.append(work)
        Task { await runDrainLoop() }
    }

    private func runDrainLoop() async {
        guard isDraining == false else { return }
        isDraining = true
        defer { isDraining = false }

        while queue.isEmpty == false {
            let work = queue.removeFirst()
            activePresentation = ActivePresentation(id: work.id, snapshot: work.snapshot)
            pendingOutcome = nil

            await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                userWaitGate = gate
            }

            _ = pendingOutcome ?? defaultOutcome(for: work.snapshot)
            pendingOutcome = nil

            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private func defaultOutcome(for snapshot: DeepTutorToolInteractionSnapshot) -> PendingOutcome {
        switch snapshot {
        case .toolPreview:
            return .toolPreviewDismissed
        }
    }

    private func resumeUserGate() {
        userWaitGate?.resume()
        userWaitGate = nil
    }
}
