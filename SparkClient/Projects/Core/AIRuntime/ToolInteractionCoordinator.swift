import Combine
import Foundation

/// 工具交互协调器
/// 核心作用：**串行处理**工具相关的人机交互（授权同意/回答问题/选择成员）
/// 设计特点：与具体UI展示形态解耦，只负责调度逻辑，保证同一时间只弹出一个交互窗口
@MainActor
final class ToolInteractionCoordinator: ObservableObject {

    /// 当前正在展示的交互弹窗（用于SwiftUI绑定显示）
    struct ActivePresentation: Identifiable, Equatable {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
    }

    /// 当前活跃的弹窗（对外可观察，UI监听这个值展示弹窗）
    @Published private(set) var activePresentation: ActivePresentation?

    /// 队列中的任务单元：包含唯一ID、交互数据、完成回调
    private struct QueuedWork {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
        /// 为nil时：仅工具预览，无异步回调
        let completion: QueuedCompletion?
    }

    /// 队列任务的回调类型（区分授权/提问/选择成员三种异步等待）
    private enum QueuedCompletion {
        /// 授权同意回调
        case consent(CheckedContinuation<InteractionResult<ToolConsentDecision>, Never>)
        /// 回答问题回调
        case question(CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>)
        /// 选择成员回调
        case member(CheckedContinuation<InteractionResult<Int>, Never>)
    }

    /// 等待用户操作后的结果类型
    private enum PendingOutcome {
        case consent(InteractionResult<ToolConsentDecision>)
        case question(InteractionResult<ToolQuestionAnswer>)
        case member(InteractionResult<Int>)
        case toolPreviewDismissed
    }

    // MARK: - 内部状态
    /// 交互任务队列（FIFO 先进先出）
    private var queue: [QueuedWork] = []
    /// 是否正在处理队列（防止重复执行）
    private var isDraining = false
    /// 用户等待门：等待用户操作的异步挂起对象
    private var userWaitGate: CheckedContinuation<Void, Never>?
    /// 待处理的用户操作结果
    private var pendingOutcome: PendingOutcome?

    // MARK: - Public API 对外接口

    /// 请求用户授权（是否允许工具使用/数据上传）
    /// - Returns: 用户授权决策结果
    func requestConsentDecision(
        threadID _: UUID?,
        result: ToolExecutionResult,
        callArguments: String,
        providerCompany: String?,
        modelName: String?,
        endpoint: String?,
        privacyPolicyURL: URL?
    ) async -> InteractionResult<ToolConsentDecision> {
        // 构建授权弹窗数据
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
        
        // 异步等待用户操作
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

    /// 请求用户回答工具提出的问题
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

    /// 请求用户选择成员
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

    /// 展示工具输出详情预览（仅展示，不等待用户回调）
    func presentToolPreview(prompt: ToolPreviewPrompt) {
        enqueue(
            QueuedWork(
                id: prompt.id,
                snapshot: .toolPreview(prompt),
                completion: nil
            )
        )
    }

    /// 关闭工具预览
    func dismissToolPreview(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .toolPreview = activePresentation?.snapshot else { return }
        pendingOutcome = .toolPreviewDismissed
        resumeUserGate()
    }

    // MARK: - 用户操作完成（同意/取消）

    /// 用户完成授权操作
    func completeConsent(id: UUID, allowed: Bool, rememberTool: Bool = false) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .consent(
            .success(
                ToolConsentDecision(
                    allowed: allowed,
                    rememberTool: allowed && rememberTool
                )
            )
        )
        resumeUserGate()
    }

    /// 用户完成问题回答
    func completeQuestion(id: UUID, answer: ToolQuestionAnswer) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .question(.success(answer))
        resumeUserGate()
    }

    /// 用户取消回答问题
    func completeQuestionCancelled(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .question(.cancelled)
        resumeUserGate()
    }

    /// 用户选择成员完成
    func completeMemberSelection(id: UUID, memberID: Int) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .member(.success(memberID))
        resumeUserGate()
    }

    /// 用户取消选择成员
    func completeMemberCancelled(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .member(.cancelled)
        resumeUserGate()
    }

    // MARK: - 队列调度核心逻辑

    /// 将任务加入队列，并触发队列执行
    private func enqueue(_ work: QueuedWork) {
        queue.append(work)
        Task { await runDrainLoop() }
    }

    /// 循环执行队列任务（**核心调度方法**）
    /// 保证：一次只处理一个交互，处理完再取下一个
    private func runDrainLoop() async {
        // 防止重复执行
        guard isDraining == false else { return }
        isDraining = true
        defer { isDraining = false }

        // 依次处理队列中所有任务
        while queue.isEmpty == false {
            let work = queue.removeFirst()
            // 设置当前展示的弹窗 → UI自动显示
            activePresentation = ActivePresentation(id: work.id, snapshot: work.snapshot)

            // 清空上一次结果，等待用户操作
            pendingOutcome = nil
            
            // 【挂起】等待用户操作（同意/取消/选择）
            await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                self.userWaitGate = gate
            }

            // 获取用户操作结果，无结果则使用默认取消
            let outcome = pendingOutcome ?? defaultOutcome(for: work.snapshot)
            
            // 清空状态
            activePresentation = nil
            pendingOutcome = nil
            
            // 恢复异步等待，返回结果给调用方
            resumeCompletion(work: work, outcome: outcome)

            // 延迟350ms：让SwiftUI完成上一个弹窗消失动画，再显示下一个
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    /// 获取交互类型对应的默认结果（用户未操作直接关闭 → 按取消处理）
    private func defaultOutcome(for snapshot: ToolInteractionSnapshot) -> PendingOutcome {
        switch snapshot {
        case .consent: return .consent(.cancelled)
        case .question: return .question(.cancelled)
        case .member: return .member(.cancelled)
        case .toolPreview: return .toolPreviewDismissed
        }
    }

    /// 恢复用户等待的异步门（继续执行队列）
    private func resumeUserGate() {
        userWaitGate?.resume()
        userWaitGate = nil
    }

    /// 根据任务类型和用户操作结果，恢复对应的异步Continuation
    private func resumeCompletion(work: QueuedWork, outcome: PendingOutcome) {
        guard let completion = work.completion else { return }
        switch (completion, outcome) {
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
