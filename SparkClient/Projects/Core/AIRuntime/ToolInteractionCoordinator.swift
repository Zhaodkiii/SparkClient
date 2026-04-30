import Combine
import Foundation

/// 串行处理工具相关人机交互（同意 / 提问 / 选成员），与具体呈现形态解耦。
@MainActor
final class ToolInteractionCoordinator: ObservableObject {
    struct ActivePresentation: Identifiable, Equatable {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
    }

    @Published private(set) var activePresentation: ActivePresentation?

    private struct QueuedWork {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
        let completion: QueuedCompletion
    }

    private enum QueuedCompletion {
        case consent(CheckedContinuation<InteractionResult<Bool>, Never>)
        case question(CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>)
        case member(CheckedContinuation<InteractionResult<Int>, Never>)
    }

    private enum PendingOutcome {
        case consent(InteractionResult<Bool>)
        case question(InteractionResult<ToolQuestionAnswer>)
        case member(InteractionResult<Int>)
    }

    private var queue: [QueuedWork] = []
    private var isDraining = false
    private var userWaitGate: CheckedContinuation<Void, Never>?
    private var pendingOutcome: PendingOutcome?

    // MARK: - Public API

    func requestConsentDecision(
        threadID _: UUID?,
        result: ToolExecutionResult,
        callArguments: String,
        providerCompany: String?,
        modelName: String?,
        endpoint: String?,
        privacyPolicyURL: URL?
    ) async -> InteractionResult<Bool> {
        guard result.requiresModelConsent else { return .success(true) }
        guard (providerCompany ?? "").uppercased() != "LOCAL" else { return .success(true) }

        let prompt = ConsentPayloadBuilder.makeSharePrompt(
            result: result,
            callArguments: callArguments,
            providerCompany: providerCompany,
            modelName: modelName,
            endpoint: endpoint,
            privacyPolicyURL: privacyPolicyURL
        )
        let id = prompt.id
        let snapshot = ToolInteractionSnapshot.consent(prompt)
        return await withCheckedContinuation { continuation in
            enqueue(
                QueuedWork(
                    id: id,
                    snapshot: snapshot,
                    completion: .consent(continuation)
                )
            )
        }
    }

    func requestQuestionAnswer(threadID _: UUID?, prompt: ToolQuestionPrompt) async -> InteractionResult<ToolQuestionAnswer> {
        let snapshot = ToolInteractionSnapshot.question(prompt)
        return await withCheckedContinuation { continuation in
            enqueue(
                QueuedWork(
                    id: prompt.id,
                    snapshot: snapshot,
                    completion: .question(continuation)
                )
            )
        }
    }

    func requestMemberSelection(threadID _: UUID?, prompt: ToolMemberSelectionPrompt) async -> InteractionResult<Int> {
        let snapshot = ToolInteractionSnapshot.member(prompt)
        return await withCheckedContinuation { continuation in
            enqueue(
                QueuedWork(
                    id: prompt.id,
                    snapshot: snapshot,
                    completion: .member(continuation)
                )
            )
        }
    }

    func completeConsent(allowed: Bool) {
        guard activePresentation != nil else { return }
        pendingOutcome = .consent(.success(allowed))
        resumeUserGate()
    }

    func completeQuestion(answer: ToolQuestionAnswer) {
        guard activePresentation != nil else { return }
        pendingOutcome = .question(.success(answer))
        resumeUserGate()
    }

    func completeQuestionCancelled() {
        guard activePresentation != nil else { return }
        pendingOutcome = .question(.cancelled)
        resumeUserGate()
    }

    func completeMemberSelection(memberID: Int) {
        guard activePresentation != nil else { return }
        pendingOutcome = .member(.success(memberID))
        resumeUserGate()
    }

    func completeMemberCancelled() {
        guard activePresentation != nil else { return }
        pendingOutcome = .member(.cancelled)
        resumeUserGate()
    }

    /// SwiftUI sheet 被手势关闭且未点主按钮时，与旧版 sheet onDismiss 一致。
    func handleInteractionSheetDismissed() {
        guard activePresentation != nil else { return }
        switch activePresentation?.snapshot {
        case .consent:
            pendingOutcome = .consent(.success(false))
        case .question:
            pendingOutcome = .question(.cancelled)
        case .member:
            pendingOutcome = .member(.cancelled)
        case .none:
            return
        }
        resumeUserGate()
    }

    // MARK: - Queue

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
                self.userWaitGate = gate
            }

            let outcome = pendingOutcome ?? defaultOutcome(for: work.snapshot)
            resumeCompletion(work: work, outcome: outcome)

            activePresentation = nil
            pendingOutcome = nil
        }
    }

    private func defaultOutcome(for snapshot: ToolInteractionSnapshot) -> PendingOutcome {
        switch snapshot {
        case .consent: return .consent(.cancelled)
        case .question: return .question(.cancelled)
        case .member: return .member(.cancelled)
        }
    }

    private func resumeUserGate() {
        userWaitGate?.resume()
        userWaitGate = nil
    }

    private func resumeCompletion(work: QueuedWork, outcome: PendingOutcome) {
        switch (work.completion, outcome) {
        case (.consent(let c), .consent(let r)):
            c.resume(returning: r)
        case (.question(let c), .question(let r)):
            c.resume(returning: r)
        case (.member(let c), .member(let r)):
            c.resume(returning: r)
        default:
            break
        }
    }
}
