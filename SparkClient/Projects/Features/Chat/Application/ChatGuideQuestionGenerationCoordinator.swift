import Foundation

/// 科普问题 AI 生成触发边界（CHAT-000028）：
/// 仅允许「新建对话首次初始化」与「用户切换当前对话绑定成员」两个业务时机触发 AI 生成。
/// 重新进入已有对话永远不是生成触发器，只允许固定兜底修复。
enum ChatGuideQuestionGenerationTrigger: Sendable {
    /// 新建对话首次初始化（thread 已绑定成员时生成一次，否则落固定问题）。
    case newlyCreatedThread
    /// 用户切换当前对话绑定成员（清空旧成员问题并重新生成）。
    case memberBindingChanged
}

struct ChatGuideQuestionGenerationToken: Equatable, Sendable {
    var threadID: UUID
    var messageID: UUID
    var blockID: UUID
    var memberID: Int
    var taskID: UUID
    var startedAt: Date
}

struct ChatGuideQuestionTaskKey: Hashable, Sendable {
    var threadID: UUID
    var messageID: UUID
    var blockID: UUID
}

struct ChatGuideGuideCardTarget: Equatable, Sendable {
    var threadID: UUID
    var message: ChatMessage
    var block: ChatMessageBlock
    var payload: ChatGuideCardPayload
}

private struct ActiveGuideQuestionTask {
    var memberID: Int
    var taskID: UUID
    var startedAt: Date
    var task: Task<Void, Never>
}

enum ChatGuideGuideCardLocator {
    /// 在当前 thread 消息中定位首条 system 引导卡片。
    static func locateFirstGuideCard(in messages: [ChatMessage]) -> ChatGuideGuideCardTarget? {
        for message in messages where message.role == .system {
            for block in message.blocks where block.kind == .chatGuideCard {
                guard case .chatGuideCard(let payload) = block.payload else { continue }
                return ChatGuideGuideCardTarget(
                    threadID: message.threadID,
                    message: message,
                    block: block,
                    payload: payload
                )
            }
        }
        return nil
    }
}

@MainActor
final class ChatGuideQuestionGenerationCoordinator {
    private let generationUseCase: ChatGuideQuestionGenerationUseCase
    private let chatRepository: any ChatRepository
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let logger: Logger
    private var activeTasks: [ChatGuideQuestionTaskKey: ActiveGuideQuestionTask] = [:]
    /// 每个 block 最近一次“被新任务取代”的 taskID：
    /// 即使新任务已完成并清除，被取消的旧任务仍能识别自己已被接管，避免误写 preset 兜底。
    private var supersededTaskIDByKey: [ChatGuideQuestionTaskKey: UUID] = [:]

    init(
        generationUseCase: ChatGuideQuestionGenerationUseCase,
        chatRepository: any ChatRepository,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.generationUseCase = generationUseCase
        self.chatRepository = chatRepository
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.logger = logger
    }

    func cancelGeneration(threadID: UUID, messageID: UUID, blockID: UUID) {
        let key = ChatGuideQuestionTaskKey(threadID: threadID, messageID: messageID, blockID: blockID)
        cancelActiveTaskAndMarkSuperseded(forKey: key)
        activeTasks[key] = nil
    }

    func cancelAll(for threadID: UUID) {
        for key in activeTasks.keys where key.threadID == threadID {
            cancelActiveTaskAndMarkSuperseded(forKey: key)
            activeTasks[key] = nil
        }
    }

    func hasActiveGeneration(threadID: UUID, messageID: UUID, blockID: UUID) -> Bool {
        let key = ChatGuideQuestionTaskKey(threadID: threadID, messageID: messageID, blockID: blockID)
        return activeTasks[key] != nil
    }

    /// 新建对话首次初始化（trigger = .newlyCreatedThread）：
    /// - 未绑定成员：直接固定三条问题，不触发 AI；
    /// - 已绑定成员：允许生成一次；失败/解码失败固定兜底。
    func startForNewThread(
        threadID: UUID,
        messages: [ChatMessage],
        stateStore: ChatStateStore,
        resolveModelName: @escaping (UUID) async -> String?
    ) async {
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages) else {
            return
        }

        let thread = await chatRepository.loadThread(id: threadID)
        guard let memberID = thread?.memberID else {
            if target.payload.questions.isEmpty {
                logger.info(
                    "chat.guide.questions.new_thread_preset thread=\(shortID(threadID)) block=\(shortID(target.block.id))",
                    module: .general
                )
                await applyPreset(
                    target: target,
                    threadID: threadID,
                    state: .preset,
                    stateStore: stateStore,
                    errorMessage: "new_thread_without_member"
                )
            }
            return
        }

        logger.info(
            "chat.guide.questions.ensure thread=\(shortID(threadID)) block=\(shortID(target.block.id)) trigger=newly_created_thread member=\(memberID)",
            module: .general
        )

        // 幂等：已有该成员的终态问题时不重复生成
        if hasTerminalQuestions(payload: target.payload, memberID: memberID) {
            return
        }
        if hasActiveGeneration(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id,
            memberID: memberID
        ) {
            return
        }

        registerGeneration(
            target: target,
            memberID: memberID,
            threadID: threadID,
            stateStore: stateStore,
            resolveModelName: resolveModelName
        )
    }

    /// 用户切换当前对话绑定成员（trigger = .memberBindingChanged）：
    /// - 新成员为 nil：取消旧任务，直接固定三条问题；
    /// - 新成员非 nil 且允许生成：清空旧成员问题并重新生成一次；
    /// - allowGeneration == false（如重新进入旧对话时的默认绑定）：只修复异常态，绝不生成。
    func handleMemberBindingChanged(
        threadID: UUID,
        newMemberID: Int?,
        messages: [ChatMessage],
        stateStore: ChatStateStore,
        resolveModelName: @escaping (UUID) async -> String?,
        allowGeneration: Bool = true
    ) async {
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages) else {
            return
        }

        logger.info(
            "chat.guide.questions.member_changed thread=\(shortID(threadID)) old=\(target.payload.questionGeneration?.memberID.map(String.init) ?? "nil") new=\(newMemberID.map(String.init) ?? "nil") allowGeneration=\(allowGeneration)",
            module: .general
        )

        guard let memberID = newMemberID else {
            cancelAll(for: threadID)
            await applyPreset(
                target: target,
                threadID: threadID,
                state: .preset,
                stateStore: stateStore,
                errorMessage: "member_unbound"
            )
            return
        }

        // 已有该成员的有效生成结果：不重复生成
        if hasTerminalQuestions(payload: target.payload, memberID: memberID) {
            return
        }
        if hasActiveGeneration(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id,
            memberID: memberID
        ) {
            return
        }

        // 非新建链路（默认绑定成员成功但不是本次新建对话）：只做固定兜底修复
        guard allowGeneration else {
            if target.payload.questions.isEmpty {
                await applyPreset(
                    target: target,
                    threadID: threadID,
                    state: .fallback,
                    stateStore: stateStore,
                    errorMessage: "recovered_from_default_binding_without_generation"
                )
            }
            return
        }

        // 注意：cancel 与重新注册之间不能有 await，避免旧取消任务误判“无新任务接管”而落 preset
        cancelAll(for: threadID)
        registerGeneration(
            target: target,
            memberID: memberID,
            threadID: threadID,
            stateStore: stateStore,
            resolveModelName: resolveModelName
        )
    }

    /// 重新进入已有对话：只允许修复异常 guide 卡片状态为固定问题，绝不触发 AI 生成。
    /// - 已有可展示 questions（generated/fallback/preset/旧版 payload）：原样展示，no-op；
    /// - generating/failed/空 questions：回写固定三条问题（errorMessage = recovered_from_stale_generating）。
    func repairGuideQuestionsForReenteredThread(
        threadID: UUID,
        messages: [ChatMessage],
        stateStore: ChatStateStore
    ) async {
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages) else {
            return
        }

        // 有活跃生成任务时不修复，避免覆盖即将回写的结果
        if hasActiveGeneration(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id
        ) {
            return
        }

        guard target.payload.questions.isEmpty else {
            return
        }

        let state = target.payload.effectiveQuestionGenerationState
        logger.info(
            "chat.guide.questions.reenter_repair_to_preset thread=\(shortID(threadID)) block=\(shortID(target.block.id)) state=\(state.rawValue)",
            module: .general
        )
        await applyPreset(
            target: target,
            threadID: threadID,
            state: .fallback,
            stateStore: stateStore,
            errorMessage: "recovered_from_stale_generating"
        )
    }

    /// payload 是否已有该成员的可展示终态问题（generated/fallback）。
    private func hasTerminalQuestions(payload: ChatGuideCardPayload, memberID: Int) -> Bool {
        let state = payload.effectiveQuestionGenerationState
        return payload.questionsBelongTo(memberID: memberID)
            && (state == .generated || state == .fallback)
            && payload.questions.isEmpty == false
    }

    /// 同步注册生成任务（注册后任务体内先落 generating 再调用 AI），保证注册与取消之间无 await 窗口。
    private func registerGeneration(
        target: ChatGuideGuideCardTarget,
        memberID: Int,
        threadID: UUID,
        stateStore: ChatStateStore,
        resolveModelName: @escaping (UUID) async -> String?
    ) {
        let key = ChatGuideQuestionTaskKey(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id
        )

        if let active = activeTasks[key], active.memberID == memberID {
            return
        }

        // 取消旧任务并标记“已被接管”，随后同步注册新任务（两者之间无 await）
        if let active = activeTasks[key] {
            active.task.cancel()
            supersededTaskIDByKey[key] = active.taskID
        }

        let taskID = UUID()
        let startedAt = Date()
        let token = ChatGuideQuestionGenerationToken(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id,
            memberID: memberID,
            taskID: taskID,
            startedAt: startedAt
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await self.markGenerating(
                token: token,
                target: target,
                stateStore: stateStore
            )
            await self.runGeneration(
                token: token,
                metricSections: target.payload.metricSections,
                stateStore: stateStore,
                resolveModelName: resolveModelName
            )
            await MainActor.run {
                self.clearActiveTaskIfMatching(key: key, taskID: taskID)
            }
        }

        activeTasks[key] = ActiveGuideQuestionTask(
            memberID: memberID,
            taskID: taskID,
            startedAt: startedAt,
            task: task
        )
    }

    private func hasActiveGeneration(
        threadID: UUID,
        messageID: UUID,
        blockID: UUID,
        memberID: Int
    ) -> Bool {
        let key = ChatGuideQuestionTaskKey(threadID: threadID, messageID: messageID, blockID: blockID)
        guard let active = activeTasks[key] else { return false }
        return active.memberID == memberID
    }

    private func clearActiveTaskIfMatching(key: ChatGuideQuestionTaskKey, taskID: UUID) {
        guard activeTasks[key]?.taskID == taskID else { return }
        activeTasks[key] = nil
    }

    private func runGeneration(
        token: ChatGuideQuestionGenerationToken,
        metricSections: [ChatGuideMetricSection],
        stateStore: ChatStateStore,
        resolveModelName: @escaping (UUID) async -> String?
    ) async {
        let started = Date()
        let modelName = await resolveModelName(token.threadID)
        logger.info(
            "chat.guide.questions.generation_start thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID) model=\(modelName ?? "default")",
            module: .general
        )

        let localeIdentifier = Locale.current.identifier
        let input = ChatGuideQuestionGenerationInput(
            threadID: token.threadID,
            messageID: token.messageID,
            blockID: token.blockID,
            memberID: token.memberID,
            localeIdentifier: localeIdentifier,
            modelName: modelName,
            metricSections: metricSections
        )

        do {
            let output = try await generationUseCase.generate(input: input)
            logger.info(
                "chat.guide.questions.generated_ready thread=\(shortID(token.threadID)) message=\(shortID(token.messageID)) block=\(shortID(token.blockID)) tokenMember=\(token.memberID) questionCount=\(output.questions.count) ids=\(output.questions.map(\.id).joined(separator: ","))",
                module: .general
            )
            let applied = await applyGenerated(
                token: token,
                output: output,
                stateStore: stateStore
            )
            if applied {
                let durationMs = Int(Date().timeIntervalSince(started) * 1000)
                logger.info(
                    "chat.guide.questions.generation_success thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID) durationMs=\(durationMs)",
                    module: .general
                )
            }
        } catch ChatGuideQuestionGenerationUseCaseError.cancelled {
            logger.info(
                "chat.guide.questions.generation_cancelled thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID)",
                module: .general
            )
            // 主动取消且无新任务接管（如新建对话唯一一次生成被取消）：
            // 落固定问题兜底，避免卡片永久 loading；有新任务接管时不干预。
            if hasNewerGenerationTask(than: token) == false {
                await applyPreset(
                    token: token,
                    state: .preset,
                    stateStore: stateStore,
                    errorMessage: "cancelled_without_takeover"
                )
            }
        } catch {
            let category = errorCategory(for: error)
            logger.warning(
                "chat.guide.questions.generation_fallback thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID) errorCategory=\(category)",
                module: .general
            )
            _ = await applyFallback(
                token: token,
                errorCategory: category,
                stateStore: stateStore
            )
        }
    }

    /// 同一 block 上是否有比 token 更新的生成任务接管（含“已被取代”的历史事实）。
    private func hasNewerGenerationTask(than token: ChatGuideQuestionGenerationToken) -> Bool {
        let key = ChatGuideQuestionTaskKey(
            threadID: token.threadID,
            messageID: token.messageID,
            blockID: token.blockID
        )
        if supersededTaskIDByKey[key] == token.taskID {
            return true
        }
        guard let active = activeTasks[key] else { return false }
        return active.taskID != token.taskID
    }

    /// 取消活跃任务并记录其 taskID 为“已被取代”（调用方负责移除 activeTasks 条目或立即覆盖注册）。
    private func cancelActiveTaskAndMarkSuperseded(forKey key: ChatGuideQuestionTaskKey) {
        guard let active = activeTasks[key] else { return }
        active.task.cancel()
        supersededTaskIDByKey[key] = active.taskID
    }

    private func markGenerating(
        token: ChatGuideQuestionGenerationToken,
        target: ChatGuideGuideCardTarget,
        stateStore: ChatStateStore
    ) async {
        var payload = target.payload
        payload.questions = []
        payload.memberID = token.memberID
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: .generating,
            source: "current_chat_ai",
            memberID: token.memberID
        )
        await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: token.threadID,
            stateStore: stateStore
        )
    }

    private func applyPreset(
        target: ChatGuideGuideCardTarget,
        threadID: UUID,
        state: ChatGuideQuestionGenerationState,
        stateStore: ChatStateStore,
        errorMessage: String? = nil
    ) async {
        var payload = target.payload
        payload.questions = ChatGuideQuestionPreset.phaseOne
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: state,
            source: "preset",
            memberID: nil,
            errorMessage: errorMessage
        )
        await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: threadID,
            stateStore: stateStore
        )
    }

    /// 取消且无接管时的兜底：以 token 定位目标 block（宽容校验），落固定问题。
    private func applyPreset(
        token: ChatGuideQuestionGenerationToken,
        state: ChatGuideQuestionGenerationState,
        stateStore: ChatStateStore,
        errorMessage: String?
    ) async {
        let messages = await chatRepository.loadMessages(threadID: token.threadID, limit: 50, before: nil)
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages),
              target.message.clientMessageID == token.messageID,
              target.block.id == token.blockID else {
            return
        }
        await applyPreset(
            target: target,
            threadID: token.threadID,
            state: state,
            stateStore: stateStore,
            errorMessage: errorMessage
        )
    }

    @discardableResult
    private func applyGenerated(
        token: ChatGuideQuestionGenerationToken,
        output: ChatGuideQuestionGenerationOutput,
        stateStore: ChatStateStore
    ) async -> Bool {
        await updateGuideBlock(
            token: token,
            phase: .generated,
            stateStore: stateStore
        ) { payload in
            payload.questions = output.questions
            payload.memberID = output.memberID
            payload.questionGeneration = ChatGuideQuestionGenerationMeta(
                state: .generated,
                source: output.source,
                memberID: output.memberID,
                memberProfileDigest: output.memberProfileDigest,
                generatedAt: output.generatedAt
            )
        }
    }

    @discardableResult
    private func applyFallback(
        token: ChatGuideQuestionGenerationToken,
        errorCategory: String,
        stateStore: ChatStateStore
    ) async -> Bool {
        await updateGuideBlock(
            token: token,
            phase: .fallback,
            stateStore: stateStore
        ) { payload in
            payload.questions = ChatGuideQuestionPreset.phaseOne
            payload.questionGeneration = ChatGuideQuestionGenerationMeta(
                state: .fallback,
                source: "preset",
                memberID: token.memberID,
                errorMessage: errorCategory
            )
        }
    }

    @discardableResult
    private func updateGuideBlock(
        token: ChatGuideQuestionGenerationToken,
        phase: GuideTokenValidationPhase,
        stateStore: ChatStateStore,
        mutate: (inout ChatGuideCardPayload) -> Void
    ) async -> Bool {
        let validation = await validateToken(token, phase: phase)
        if let failure = validation.failure {
            logger.info(
                "chat.guide.questions.validate_failed phase=\(phase.rawValue) reason=\(failure.rawValue) thread=\(shortID(token.threadID)) message=\(shortID(token.messageID)) block=\(shortID(token.blockID)) tokenMember=\(token.memberID) threadMember=\(validation.threadMemberID.map(String.init) ?? "nil") payloadMember=\(validation.payloadMemberID.map(String.init) ?? "nil") state=\(validation.payloadState?.rawValue ?? "nil") questionsCount=\(validation.questionsCount)",
                module: .general
            )
            return false
        }

        guard let target = validation.target else { return false }

        var payload = target.payload
        mutate(&payload)
        return await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: token.threadID,
            stateStore: stateStore
        )
    }

    @discardableResult
    private func persistPayloadUpdate(
        target: ChatGuideGuideCardTarget,
        payload: ChatGuideCardPayload,
        threadID: UUID,
        stateStore: ChatStateStore
    ) async -> Bool {
        let updatedBlock = target.block.replacingPayload(.chatGuideCard(payload), status: .ready)
        let state = payload.effectiveQuestionGenerationState
        logger.info(
            "chat.guide.questions.persist_attempt thread=\(shortID(threadID)) message=\(shortID(target.message.clientMessageID)) block=\(shortID(target.block.id)) state=\(state.rawValue) member=\(payload.questionGeneration?.memberID.map(String.init) ?? "nil") questionsCount=\(payload.questions.count) oldRevision=\(target.block.revision) newRevision=\(updatedBlock.revision) markPendingForSync=true",
            module: .general
        )
        let didApply = await chatRepository.upsertMessageBlock(
            clientMessageID: target.message.clientMessageID,
            block: updatedBlock,
            markPendingForSync: true
        )
        guard didApply else {
            logger.warning(
                "chat.guide.questions.persist_result didApply=false thread=\(shortID(threadID)) message=\(shortID(target.message.clientMessageID)) block=\(shortID(target.block.id)) state=\(state.rawValue) questionsCount=\(payload.questions.count) oldRevision=\(target.block.revision) newRevision=\(updatedBlock.revision)",
                module: .general
            )
            return false
        }

        let updatedMessage = target.message.replacingBlocks(
            target.message.blocks.map { $0.id == updatedBlock.id ? updatedBlock : $0 }
        )
        stateStore.updateMessages([updatedMessage], for: threadID)
        logger.info(
            "chat.guide.questions.persist_result didApply=true thread=\(shortID(threadID)) message=\(shortID(target.message.clientMessageID)) block=\(shortID(target.block.id)) state=\(state.rawValue) questionsCount=\(payload.questions.count)",
            module: .general
        )
        logger.info(
            "chat.guide.questions.ui_update_enqueued thread=\(shortID(threadID)) message=\(shortID(target.message.clientMessageID)) block=\(shortID(target.block.id)) state=\(state.rawValue) questionsCount=\(payload.questions.count)",
            module: .general
        )
        return true
    }

    // MARK: - Token 校验

    private enum GuideTokenValidationPhase: String {
        /// AI 成功结果回写（严格，但允许修复生成中空卡片缺失的 memberID）
        case generated
        /// 失败固定兜底回写（宽容修复）
        case fallback
    }

    private enum GuideTokenValidationFailure: String {
        case threadNotFound
        case threadMemberMismatch
        case targetNotFound
        case newerResultExists
        case payloadMemberMismatch
        case fallbackTargetNotRepairable
    }

    private struct GuideTokenValidationResult {
        var failure: GuideTokenValidationFailure?
        var target: ChatGuideGuideCardTarget?
        var threadMemberID: Int?
        var payloadMemberID: Int?
        var payloadState: ChatGuideQuestionGenerationState?
        var questionsCount: Int = 0
    }

    /// generated 阶段校验规则（CHAT-000028 3.4）：
    /// 1. thread.memberID 必须等于 token.memberID（成员切换硬校验）；
    /// 2. message/block 必须匹配；
    /// 3. payload.questionGeneration.memberID == token.memberID -> 允许；
    /// 4. payload.questionGeneration.memberID == nil 且 state == generating 且 questions 为空
    ///    -> 允许，并在 generated payload 中补齐 memberID；
    /// 5. payload.questionGeneration.memberID 是其他成员 -> 拦截。
    private func validateToken(
        _ token: ChatGuideQuestionGenerationToken,
        phase: GuideTokenValidationPhase
    ) async -> GuideTokenValidationResult {
        guard let thread = await chatRepository.loadThread(id: token.threadID) else {
            return GuideTokenValidationResult(failure: .threadNotFound, target: nil, threadMemberID: nil, payloadMemberID: nil, payloadState: nil)
        }
        guard thread.memberID == token.memberID else {
            return GuideTokenValidationResult(
                failure: .threadMemberMismatch,
                target: nil,
                threadMemberID: thread.memberID,
                payloadMemberID: nil,
                payloadState: nil
            )
        }

        let messages = await chatRepository.loadMessages(threadID: token.threadID, limit: 50, before: nil)
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages),
              target.message.clientMessageID == token.messageID,
              target.block.id == token.blockID else {
            return GuideTokenValidationResult(
                failure: .targetNotFound,
                target: nil,
                threadMemberID: thread.memberID,
                payloadMemberID: nil,
                payloadState: nil
            )
        }

        let payloadMemberID = target.payload.questionGeneration?.memberID
        let state = target.payload.effectiveQuestionGenerationState
        var result = GuideTokenValidationResult(
            failure: nil,
            target: target,
            threadMemberID: thread.memberID,
            payloadMemberID: payloadMemberID,
            payloadState: state,
            questionsCount: target.payload.questions.count
        )

        if phase == .generated {
            // 已有更新的成功/兜底结果：拦截旧结果
            if state == .generated || state == .fallback,
               let generatedAt = target.payload.questionGeneration?.generatedAt,
               generatedAt > token.startedAt,
               payloadMemberID == token.memberID {
                result.failure = .newerResultExists
                return result
            }
            if payloadMemberID == token.memberID {
                return result
            }
            // 生成中空卡片缺少 memberID（历史 bug 数据）：同成员时允许回写并补齐
            if payloadMemberID == nil,
               state == .generating,
               target.payload.questions.isEmpty {
                return result
            }
            result.failure = .payloadMemberMismatch
            return result
        }

        // fallback 阶段：宽容修复
        if payloadMemberID == token.memberID {
            return result
        }
        if payloadMemberID == nil,
           state == .generating || target.payload.questions.isEmpty {
            return result
        }
        if target.payload.questionGeneration == nil,
           target.payload.questions.isEmpty {
            return result
        }
        result.failure = .fallbackTargetNotRepairable
        return result
    }

    private func errorCategory(for error: Error) -> String {
        switch error {
        case ChatGuideQuestionGenerationUseCaseError.memberProfileUnavailable:
            return "member_profile_unavailable"
        case ChatGuideQuestionGenerationUseCaseError.aiGenerationFailed:
            return "ai_generation_failed"
        case ChatGuideQuestionGenerationUseCaseError.parseFailed(let stage, let parserError, _):
            return "parse_failed_\(stage.rawValue)_\(parserError)"
        case ChatGuideQuestionGenerationUseCaseError.cancelled:
            return "cancelled"
        default:
            return "unknown"
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
