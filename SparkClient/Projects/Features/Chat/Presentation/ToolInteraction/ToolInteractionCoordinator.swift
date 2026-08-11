import Combine
import Foundation

@MainActor
protocol ChatInlineToolInteractionCardSink: AnyObject {
    func presentInlineQuestionCard(
        threadID: UUID?,
        prompt: ToolQuestionPrompt,
        completionID: UUID,
        toolCallID: String?
    ) async -> Bool

    func presentInlineMemberSelectionCard(
        threadID: UUID?,
        prompt: ToolMemberSelectionPrompt,
        completionID: UUID,
        toolCallID: String?
    ) async -> Bool

    func presentInlineHealthResourceCandidateCard(
        threadID: UUID?,
        prompt: HealthResourceToolCandidatePrompt,
        completionID: UUID,
        toolCallID: String?
    ) async -> Bool

    func presentInlineToolConsentCard(
        threadID: UUID?,
        prompt: ExternalToolDataSharePrompt,
        completionID: UUID,
        toolCallID: String?
    ) async -> Bool

    func presentInlineAttachmentCaptureCard(
        threadID: UUID?,
        prompt: ToolAttachmentCapturePrompt,
        completionID: UUID,
        toolCallID: String?
    ) async -> Bool
}

enum ToolInteractionCancelReason: String, Sendable {
    case userStoppedGeneration
}

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

    /// 队列任务的回调类型（区分授权/提问/选择成员/健康资料候选等异步等待）
    private enum QueuedCompletion {
        /// 授权同意回调
        case consent(CheckedContinuation<InteractionResult<ToolConsentDecision>, Never>)
        /// 回答问题回调
        case question(CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>)
        /// 选择成员回调
        case member(CheckedContinuation<InteractionResult<Int>, Never>)
        /// 健康资料候选确认回调
        case healthResourceCandidates(CheckedContinuation<InteractionResult<[HealthResourceToolCandidateDTO]>, Never>)
        case attachmentCapture(CheckedContinuation<InteractionResult<ToolAttachmentCaptureResult>, Never>)
    }

    /// 等待用户操作后的结果类型
    private enum PendingOutcome {
        case consent(InteractionResult<ToolConsentDecision>)
        case question(InteractionResult<ToolQuestionAnswer>)
        case member(InteractionResult<Int>)
        case healthResourceCandidates(InteractionResult<[HealthResourceToolCandidateDTO]>)
        case attachmentCapture(InteractionResult<ToolAttachmentCaptureResult>)
        case toolPreviewDismissed
        case systemMessageSettingsDismissed
        case askReportPickerDismissed
        case apiKeysSettingsDismissed
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
    private var inlineQuestionContinuations: [UUID: CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>] = [:]
    private var inlineMemberContinuations: [UUID: CheckedContinuation<InteractionResult<Int>, Never>] = [:]
    private var inlineHealthResourceCandidateContinuations: [UUID: CheckedContinuation<InteractionResult<[HealthResourceToolCandidateDTO]>, Never>] = [:]
    private var inlineConsentContinuations: [UUID: CheckedContinuation<InteractionResult<ToolConsentDecision>, Never>] = [:]
    private var inlineAttachmentCaptureContinuations: [UUID: CheckedContinuation<InteractionResult<ToolAttachmentCaptureResult>, Never>] = [:]
    weak var inlineCardSink: (any ChatInlineToolInteractionCardSink)?
    private var interactionPreferences: ChatToolInteractionPreferences = .default

    func configureInlineCardSink(_ sink: (any ChatInlineToolInteractionCardSink)?) {
        inlineCardSink = sink
    }

    func updateInteractionPreferences(_ preferences: ChatToolInteractionPreferences) {
        interactionPreferences = preferences
    }

    func cancelAllPendingInteractions(reason: ToolInteractionCancelReason) {
        if let activePresentation, pendingOutcome == nil {
            pendingOutcome = defaultOutcome(for: activePresentation.snapshot)
            resumeUserGate()
        } else {
            activePresentation = nil
            pendingOutcome = nil
            resumeUserGate()
        }

        let queuedWork = queue
        queue.removeAll()
        queuedWork.forEach { work in
            resumeCompletion(work: work, outcome: defaultOutcome(for: work.snapshot))
        }

        let questionContinuations = inlineQuestionContinuations
        inlineQuestionContinuations.removeAll()
        questionContinuations.values.forEach { $0.resume(returning: .cancelled) }

        let memberContinuations = inlineMemberContinuations
        inlineMemberContinuations.removeAll()
        memberContinuations.values.forEach { $0.resume(returning: .cancelled) }

        let healthResourceContinuations = inlineHealthResourceCandidateContinuations
        inlineHealthResourceCandidateContinuations.removeAll()
        healthResourceContinuations.values.forEach { $0.resume(returning: .cancelled) }

        let consentContinuations = inlineConsentContinuations
        inlineConsentContinuations.removeAll()
        consentContinuations.values.forEach { $0.resume(returning: .cancelled) }

        let attachmentContinuations = inlineAttachmentCaptureContinuations
        inlineAttachmentCaptureContinuations.removeAll()
        attachmentContinuations.values.forEach { $0.resume(returning: .cancelled) }
    }

    func hasPendingInlineInteraction(completionID: UUID) -> Bool {
        inlineQuestionContinuations[completionID] != nil
            || inlineMemberContinuations[completionID] != nil
            || inlineHealthResourceCandidateContinuations[completionID] != nil
            || inlineConsentContinuations[completionID] != nil
            || inlineAttachmentCaptureContinuations[completionID] != nil
    }

    // MARK: - Public API 对外接口

    /// 请求用户授权（是否允许工具使用/数据上传）
    /// - Returns: 用户授权决策结果
    func requestConsentDecision(
        threadID: UUID?,
        result: ToolExecutionResult,
        callArguments: String,
        providerCompany: String?,
        modelName: String?,
        endpoint: String?,
        privacyPolicyURL: URL?,
        toolCallID: String? = nil
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
        if interactionPreferences.consentPresentationMode == .inlineCard,
           let inlineCardSink {
            return await requestInlineConsentDecision(
                threadID: threadID,
                prompt: prompt,
                toolCallID: toolCallID,
                sink: inlineCardSink
            )
        }
        return await requestConsentDecisionSheet(prompt: prompt)
    }

    func requestConsentDecisionSheet(
        prompt: ExternalToolDataSharePrompt
    ) async -> InteractionResult<ToolConsentDecision> {
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
    func requestQuestionAnswer(
        threadID: UUID?,
        prompt: ToolQuestionPrompt,
        toolCallID: String? = nil
    ) async -> InteractionResult<ToolQuestionAnswer> {
        if interactionPreferences.questionPresentationMode == .inlineCard,
           let inlineCardSink {
            return await requestInlineQuestionAnswer(
                threadID: threadID,
                prompt: prompt,
                toolCallID: toolCallID,
                sink: inlineCardSink
            )
        }
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
    func requestMemberSelection(
        threadID: UUID?,
        prompt: ToolMemberSelectionPrompt,
        toolCallID: String? = nil,
        sourceToolName: String? = nil
    ) async -> InteractionResult<Int> {
        let presentationMode = memberSelectionPresentationMode(for: sourceToolName)
        if presentationMode == .inlineCard,
           let inlineCardSink {
            return await requestInlineMemberSelection(
                threadID: threadID,
                prompt: prompt,
                toolCallID: toolCallID,
                sink: inlineCardSink
            )
        }
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

    private func memberSelectionPresentationMode(
        for sourceToolName: String?
    ) -> ChatToolInteractionPresentationMode {
        switch sourceToolName {
        case SparkToolName.queryMemberProfile.rawValue:
            return interactionPreferences.memberProfilePresentationMode
        default:
            return interactionPreferences.memberSelectionPresentationMode
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

    func presentSystemMessageSettings(prompt: SystemMessageSettingsPrompt) {
        enqueue(
            QueuedWork(
                id: prompt.id,
                snapshot: .systemMessageSettings(prompt),
                completion: nil
            )
        )
    }

    /// 展示 API Keys 设置（仅展示，不等待用户回调）
    func presentAPIKeysSettings() {
        enqueue(
            QueuedWork(
                id: UUID(),
                snapshot: .apiKeysSettings,
                completion: nil
            )
        )
    }

    /// 请求用户确认健康资料候选（阻塞直至确认或取消，与敏感数据授权一致）。
    func requestHealthResourceCandidateSelection(
        prompt: HealthResourceToolCandidatePrompt,
        toolCallID: String? = nil
    ) async -> InteractionResult<[HealthResourceToolCandidateDTO]> {
        if let inlineCardSink {
            return await requestInlineHealthResourceCandidateSelection(
                threadID: prompt.threadID,
                prompt: prompt,
                toolCallID: toolCallID,
                sink: inlineCardSink
            )
        }
        return await requestHealthResourceCandidateSelectionSheet(prompt: prompt)
    }

    func requestHealthResourceCandidateSelectionSheet(
        prompt: HealthResourceToolCandidatePrompt
    ) async -> InteractionResult<[HealthResourceToolCandidateDTO]> {
        let snapshot = ToolInteractionSnapshot.healthResourceCandidates(prompt)
        return await withCheckedContinuation { continuation in
            enqueue(
                QueuedWork(
                    id: prompt.id,
                    snapshot: snapshot,
                    completion: .healthResourceCandidates(continuation)
                )
            )
        }
    }

    func requestAttachmentCapture(
        threadID: UUID?,
        prompt: ToolAttachmentCapturePrompt,
        toolCallID: String? = nil
    ) async -> InteractionResult<ToolAttachmentCaptureResult> {
        SparkLogger.log(
            level: .info,
            module: .general,
            message: "[CHAT-000017][ToolInteraction] requestAttachmentCapture thread=\(threadID?.uuidString ?? "-") prompt=\(prompt.id.uuidString) type=\(prompt.cardType.rawValue) toolCall=\(toolCallID ?? "-") hasInlineSink=\(inlineCardSink != nil)"
        )
        if let inlineCardSink {
            return await requestInlineAttachmentCapture(
                threadID: threadID,
                prompt: prompt,
                toolCallID: toolCallID,
                sink: inlineCardSink
            )
        }
        SparkLogger.log(
            level: .warning,
            module: .general,
            message: "[CHAT-000017][ToolInteraction] requestAttachmentCapture cancelled: missing inline sink prompt=\(prompt.id.uuidString)"
        )
        return .cancelled
    }

    /// 关闭工具预览
    func dismissToolPreview(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .toolPreview = activePresentation?.snapshot else { return }
        pendingOutcome = .toolPreviewDismissed
        resumeUserGate()
    }

    func dismissSystemMessageSettings(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .systemMessageSettings = activePresentation?.snapshot else { return }
        pendingOutcome = .systemMessageSettingsDismissed
        resumeUserGate()
    }

    func dismissAPIKeysSettings(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .apiKeysSettings = activePresentation?.snapshot else { return }
        pendingOutcome = .apiKeysSettingsDismissed
        resumeUserGate()
    }

    func completeHealthResourceCandidates(id: UUID, selected: [HealthResourceToolCandidateDTO]) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .healthResourceCandidates(.success(selected))
        resumeUserGate()
    }

    func completeHealthResourceCandidatesCancelled(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        pendingOutcome = .healthResourceCandidates(.cancelled)
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

    func completeInlineQuestion(id: UUID, answer: ToolQuestionAnswer) {
        guard let continuation = inlineQuestionContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .success(answer))
    }

    func completeInlineMemberSelection(id: UUID, memberID: Int) {
        guard let continuation = inlineMemberContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .success(memberID))
    }

    func cancelInlineQuestion(id: UUID) {
        guard let continuation = inlineQuestionContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .cancelled)
    }

    func cancelInlineMemberSelection(id: UUID) {
        guard let continuation = inlineMemberContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .cancelled)
    }

    func completeInlineHealthResourceCandidates(id: UUID, selected: [HealthResourceToolCandidateDTO]) {
        guard let continuation = inlineHealthResourceCandidateContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .success(selected))
    }

    func cancelInlineHealthResourceCandidates(id: UUID) {
        guard let continuation = inlineHealthResourceCandidateContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .cancelled)
    }

    func completeInlineConsent(id: UUID, decision: ToolConsentDecision) {
        guard let continuation = inlineConsentContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .success(decision))
    }

    func cancelInlineConsent(id: UUID) {
        guard let continuation = inlineConsentContinuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: .cancelled)
    }

    func completeInlineAttachmentCapture(id: UUID, result: ToolAttachmentCaptureResult) {
        guard let continuation = inlineAttachmentCaptureContinuations.removeValue(forKey: id) else {
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "[CHAT-000017][ToolInteraction] completeInlineAttachmentCapture ignored: no continuation completion=\(id.uuidString) count=\(result.attachments.count)"
            )
            return
        }
        SparkLogger.log(
            level: .info,
            module: .general,
            message: "[CHAT-000017][ToolInteraction] completeInlineAttachmentCapture resume completion=\(id.uuidString) type=\(result.cardType.rawValue) count=\(result.attachments.count) contextChars=\(result.modelContextText.count)"
        )
        continuation.resume(returning: .success(result))
    }

    func cancelInlineAttachmentCapture(id: UUID) {
        guard let continuation = inlineAttachmentCaptureContinuations.removeValue(forKey: id) else {
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "[CHAT-000017][ToolInteraction] cancelInlineAttachmentCapture ignored: no continuation completion=\(id.uuidString)"
            )
            return
        }
        SparkLogger.log(
            level: .info,
            module: .general,
            message: "[CHAT-000017][ToolInteraction] cancelInlineAttachmentCapture resume completion=\(id.uuidString)"
        )
        continuation.resume(returning: .cancelled)
    }

    private func requestInlineQuestionAnswer(
        threadID: UUID?,
        prompt: ToolQuestionPrompt,
        toolCallID: String?,
        sink: any ChatInlineToolInteractionCardSink
    ) async -> InteractionResult<ToolQuestionAnswer> {
        let completionID = UUID()
        return await withCheckedContinuation { continuation in
            inlineQuestionContinuations[completionID] = continuation
            Task {
                let didPresent = await sink.presentInlineQuestionCard(
                    threadID: threadID,
                    prompt: prompt,
                    completionID: completionID,
                    toolCallID: toolCallID
                )
                if didPresent == false {
                    await MainActor.run {
                        self.cancelInlineQuestion(id: completionID)
                    }
                }
            }
        }
    }

    private func requestInlineMemberSelection(
        threadID: UUID?,
        prompt: ToolMemberSelectionPrompt,
        toolCallID: String?,
        sink: any ChatInlineToolInteractionCardSink
    ) async -> InteractionResult<Int> {
        let completionID = UUID()
        return await withCheckedContinuation { continuation in
            inlineMemberContinuations[completionID] = continuation
            Task {
                let didPresent = await sink.presentInlineMemberSelectionCard(
                    threadID: threadID,
                    prompt: prompt,
                    completionID: completionID,
                    toolCallID: toolCallID
                )
                if didPresent == false {
                    await MainActor.run {
                        self.cancelInlineMemberSelection(id: completionID)
                    }
                }
            }
        }
    }

    private func requestInlineHealthResourceCandidateSelection(
        threadID: UUID?,
        prompt: HealthResourceToolCandidatePrompt,
        toolCallID: String?,
        sink: any ChatInlineToolInteractionCardSink
    ) async -> InteractionResult<[HealthResourceToolCandidateDTO]> {
        let completionID = UUID()
        return await withCheckedContinuation { continuation in
            inlineHealthResourceCandidateContinuations[completionID] = continuation
            Task {
                let didPresent = await sink.presentInlineHealthResourceCandidateCard(
                    threadID: threadID,
                    prompt: prompt,
                    completionID: completionID,
                    toolCallID: toolCallID
                )
                if didPresent == false {
                    await MainActor.run {
                        self.cancelInlineHealthResourceCandidates(id: completionID)
                    }
                }
            }
        }
    }

    private func requestInlineConsentDecision(
        threadID: UUID?,
        prompt: ExternalToolDataSharePrompt,
        toolCallID: String?,
        sink: any ChatInlineToolInteractionCardSink
    ) async -> InteractionResult<ToolConsentDecision> {
        let completionID = UUID()
        return await withCheckedContinuation { continuation in
            inlineConsentContinuations[completionID] = continuation
            Task {
                let didPresent = await sink.presentInlineToolConsentCard(
                    threadID: threadID,
                    prompt: prompt,
                    completionID: completionID,
                    toolCallID: toolCallID
                )
                if didPresent == false {
                    await MainActor.run {
                        self.cancelInlineConsent(id: completionID)
                    }
                }
            }
        }
    }

    private func requestInlineAttachmentCapture(
        threadID: UUID?,
        prompt: ToolAttachmentCapturePrompt,
        toolCallID: String?,
        sink: any ChatInlineToolInteractionCardSink
    ) async -> InteractionResult<ToolAttachmentCaptureResult> {
        let completionID = UUID()
        SparkLogger.log(
            level: .info,
            module: .general,
            message: "[CHAT-000017][ToolInteraction] requestInlineAttachmentCapture create continuation completion=\(completionID.uuidString) prompt=\(prompt.id.uuidString) type=\(prompt.cardType.rawValue)"
        )
        return await withCheckedContinuation { continuation in
            inlineAttachmentCaptureContinuations[completionID] = continuation
            Task {
                let didPresent = await sink.presentInlineAttachmentCaptureCard(
                    threadID: threadID,
                    prompt: prompt,
                    completionID: completionID,
                    toolCallID: toolCallID
                )
                SparkLogger.log(
                    level: didPresent ? .info : .warning,
                    module: .general,
                    message: "[CHAT-000017][ToolInteraction] requestInlineAttachmentCapture present result completion=\(completionID.uuidString) didPresent=\(didPresent)"
                )
                if didPresent == false {
                    await MainActor.run {
                        self.cancelInlineAttachmentCapture(id: completionID)
                    }
                }
            }
        }
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
        case .systemMessageSettings: return .systemMessageSettingsDismissed
        case .healthResourceCandidates: return .healthResourceCandidates(.cancelled)
        case .askReportPicker: return .askReportPickerDismissed
        case .apiKeysSettings: return .apiKeysSettingsDismissed
        }
    }

    /// 用户手势关闭当前可关闭的 Sheet（View 层无需感知 snapshot 类型）。
    func dismissActivePresentationByUser() {
        guard let active = activePresentation, pendingOutcome == nil else { return }
        switch active.snapshot {
        case .toolPreview:
            dismissToolPreview(id: active.id)
        case .systemMessageSettings:
            dismissSystemMessageSettings(id: active.id)
        case .healthResourceCandidates:
            completeHealthResourceCandidatesCancelled(id: active.id)
        case .askReportPicker:
            completeAskReportPickerCancelled(id: active.id)
        case .apiKeysSettings:
            dismissAPIKeysSettings(id: active.id)
        case .consent, .question, .member:
            break
        }
    }

    func presentAskReportPicker(prompt: AskReportPickerPrompt) {
        enqueue(
            QueuedWork(
                id: prompt.id,
                snapshot: .askReportPicker(prompt),
                completion: nil
            )
        )
    }

    func completeAskReportPickerCancelled(id: UUID) {
        guard activePresentation?.id == id, pendingOutcome == nil else { return }
        guard case .askReportPicker = activePresentation?.snapshot else { return }
        pendingOutcome = .askReportPickerDismissed
        resumeUserGate()
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
        case (.healthResourceCandidates(let c), .healthResourceCandidates(let r)):
            c.resume(returning: r)
        case (.attachmentCapture(let c), .attachmentCapture(let r)):
            c.resume(returning: r)
        default:
            break
        }
    }
}
