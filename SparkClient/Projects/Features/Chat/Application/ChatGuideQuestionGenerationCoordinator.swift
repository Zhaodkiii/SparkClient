import Foundation

/// 科普问题 AI 生成触发边界（CHAT-000028 需求核心）：
/// 严格收口生成触发时机，仅允许两个业务场景触发 AI 生成，避免重复生成和资源浪费：
/// 1. 新建对话首次初始化
/// 2. 用户手动切换当前对话绑定成员
/// - Important: 重新进入已有对话永远不会触发 AI 生成，只允许用固定问题兜底修复异常状态
enum ChatGuideQuestionGenerationTrigger: Sendable {
    /// 新建对话首次初始化触发
    /// - 对话已绑定成员：触发一次 AI 生成，失败/解码失败用固定问题兜底
    /// - 对话未绑定成员：直接落固定三条问题，不调用 AI
    case newlyCreatedThread
    /// 用户切换当前对话绑定成员触发
    /// - 清空旧成员的问题，为新成员重新生成一次
    /// - 新成员为 nil 时直接落固定问题
    case memberBindingChanged
}

/// 生成任务令牌：标识一次具体的 AI 生成请求，用于并发控制和结果校验
/// - Note: 遵循 Equatable 和 Sendable，支持并发安全比对和传递
struct ChatGuideQuestionGenerationToken: Equatable, Sendable {
    /// 会话线程 ID
    var threadID: UUID
    /// 消息客户端 ID
    var messageID: UUID
    /// 引导卡片 block ID
    var blockID: UUID
    /// 生成针对的成员 ID
    var memberID: Int
    /// 本次任务唯一 ID，用于区分新旧任务
    var taskID: UUID
    /// 任务启动时间，用于判断结果新旧
    var startedAt: Date
}

/// 生成任务唯一键：用三元组定位一个引导卡片位置的任务
/// - Note: 遵循 Hashable，可作为字典 Key
struct ChatGuideQuestionTaskKey: Hashable, Sendable {
    /// 会话线程 ID
    var threadID: UUID
    /// 消息客户端 ID
    var messageID: UUID
    /// 引导卡片 block ID
    var blockID: UUID
}

/// 引导卡片定位结果：定位到的引导卡片完整上下文
struct ChatGuideGuideCardTarget: Equatable, Sendable {
    /// 会话线程 ID
    var threadID: UUID
    /// 引导卡片所在的消息对象
    var message: ChatMessage
    /// 引导卡片对应的 block 对象
    var block: ChatMessageBlock
    /// 引导卡片 payload 数据
    var payload: ChatGuideCardPayload
}

/// 活跃生成任务上下文（内部使用）
private struct ActiveGuideQuestionTask {
    /// 任务针对的成员 ID
    var memberID: Int
    /// 任务唯一 ID
    var taskID: UUID
    /// 任务启动时间
    var startedAt: Date
    /// 实际执行的 Task 对象，可用于取消
    var task: Task<Void, Never>
}

/// 引导卡片定位器：在消息列表中查找引导卡片
enum ChatGuideGuideCardLocator {
    /// 在当前 thread 的消息列表中定位首条 system 类型消息中的引导卡片
    /// - Parameter messages: 消息列表
    /// - Returns: 找到则返回引导卡片目标上下文，找不到返回 nil
    /// - Note: 只查找第一条 system 消息中的第一个 chatGuideCard 类型 block
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

/// 聊天引导问题生成协调器
/// - Important: 核心职责：
///   1. 严格控制 AI 生成触发边界，仅在允许的时机触发
///   2. 管理并发生成任务，处理任务取消、竞态条件和新旧任务接管
///   3. 处理生成成功、失败、取消等各类场景的状态回写
///   4. 异常状态兜底修复，避免引导卡片永久 loading
/// - Note: 标记为 @MainActor，所有状态修改和 UI 更新都在主线程执行
@MainActor
final class ChatGuideQuestionGenerationCoordinator {
    /// 引导问题生成用例，实际执行 AI 调用逻辑
    private let generationUseCase: ChatGuideQuestionGenerationUseCase
    /// 聊天数据仓库，用于读写线程、消息、block 数据
    private let chatRepository: any ChatRepository
    /// AI 配置中心
    private let aiConfigCenter: AIConfigCenter
    /// AI 设置仓库
    private let aiSettingsRepository: any AISettingsRepository
    /// 生成问题登记上送（后台异步 best-effort；nil 表示不登记，测试/预览场景可省略）
    private let registrationReporter: (any ChatGuideQuestionRegistrationReporting)?
    /// 日志记录器
    private let logger: Logger
    /// 当前活跃的生成任务字典，Key 为任务定位键，Value 为任务上下文
    private var activeTasks: [ChatGuideQuestionTaskKey: ActiveGuideQuestionTask] = [:]
    /// 每个 block 最近一次"被新任务取代"的 taskID 记录
    /// - Important: 核心并发安全机制：即使新任务已完成并从 activeTasks 清除，
    ///   被取消的旧任务仍能通过此表识别自己已被接管，避免误写 preset 兜底覆盖新结果
    private var supersededTaskIDByKey: [ChatGuideQuestionTaskKey: UUID] = [:]

    /// 初始化引导问题生成协调器
    /// - Parameters:
    ///   - generationUseCase: AI 生成用例
    ///   - chatRepository: 聊天数据仓库
    ///   - aiConfigCenter: AI 配置中心
    ///   - aiSettingsRepository: AI 设置仓库
    ///   - logger: 日志记录器，默认使用 ConsoleLogger()
    init(
        generationUseCase: ChatGuideQuestionGenerationUseCase,
        chatRepository: any ChatRepository,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        registrationReporter: (any ChatGuideQuestionRegistrationReporting)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.generationUseCase = generationUseCase
        self.chatRepository = chatRepository
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.registrationReporter = registrationReporter
        self.logger = logger
    }

    /// 取消指定位置的生成任务
    /// - Parameters:
    ///   - threadID: 会话线程 ID
    ///   - messageID: 消息 ID
    ///   - blockID: 引导卡片 block ID
    func cancelGeneration(threadID: UUID, messageID: UUID, blockID: UUID) {
        let key = ChatGuideQuestionTaskKey(threadID: threadID, messageID: messageID, blockID: blockID)
        cancelActiveTaskAndMarkSuperseded(forKey: key)
        activeTasks[key] = nil
    }

    /// 取消指定线程下的所有生成任务
    /// - Parameter threadID: 会话线程 ID
    func cancelAll(for threadID: UUID) {
        for key in activeTasks.keys where key.threadID == threadID {
            cancelActiveTaskAndMarkSuperseded(forKey: key)
            activeTasks[key] = nil
        }
    }

    /// 检查指定位置是否有正在进行的生成任务
    /// - Parameters:
    ///   - threadID: 会话线程 ID
    ///   - messageID: 消息 ID
    ///   - blockID: 引导卡片 block ID
    /// - Returns: 有活跃任务返回 true，否则返回 false
    func hasActiveGeneration(threadID: UUID, messageID: UUID, blockID: UUID) -> Bool {
        let key = ChatGuideQuestionTaskKey(threadID: threadID, messageID: messageID, blockID: blockID)
        return activeTasks[key] != nil
    }

    /// 新建对话首次初始化入口（trigger = .newlyCreatedThread）
    ///
    /// 处理逻辑：
    /// - 未绑定成员：直接写入固定三条问题，不触发 AI 生成
    /// - 已绑定成员：触发一次 AI 生成；生成失败/JSON 解析失败时用固定问题兜底
    /// - 幂等保证：已有该成员的终态问题或已有相同成员的活跃任务时，不重复生成
    ///
    /// - Parameters:
    ///   - threadID: 新建对话的线程 ID
    ///   - messages: 当前消息列表
    ///   - stateStore: 聊天状态存储，用于更新 UI
    ///   - resolveModelName: 模型名称解析闭包，根据线程 ID 获取应使用的 AI 模型
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
            // 新建对话未绑定成员：直接落固定问题
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

        // 幂等校验 1：已有该成员的终态问题时不重复生成
        if hasTerminalQuestions(payload: target.payload, memberID: memberID) {
            return
        }
        // 幂等校验 2：已有针对该成员的活跃生成任务时不重复启动
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

    /// 用户切换当前对话绑定成员入口（trigger = .memberBindingChanged）
    ///
    /// 处理逻辑：
    /// - 新成员为 nil：取消所有旧任务，直接写入固定三条问题
    /// - 新成员非 nil 且 allowGeneration = true：清空旧成员问题，为新成员重新生成一次
    /// - allowGeneration = false（如重新进入旧对话时的默认成员绑定）：仅修复异常状态，绝不触发 AI 生成
    /// - 幂等保证：已有该成员的有效结果或活跃任务时不重复生成
    ///
    /// - Important: 取消旧任务和注册新任务之间不能有 await 断点，避免竞态条件
    ///
    /// - Parameters:
    ///   - threadID: 会话线程 ID
    ///   - newMemberID: 新绑定的成员 ID，为 nil 表示解绑成员
    ///   - messages: 当前消息列表
    ///   - stateStore: 聊天状态存储
    ///   - resolveModelName: 模型名称解析闭包
    ///   - allowGeneration: 是否允许触发 AI 生成，默认 true
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
            "chat.guide.questions.member_changed thread=\(shortID(threadID)) old=\(target.payload.questionGeneration?.memberId.map(String.init) ?? "nil") new=\(newMemberID.map(String.init) ?? "nil") allowGeneration=\(allowGeneration)",
            module: .general
        )

        guard let memberID = newMemberID else {
            // 解绑成员：取消所有任务并落固定问题
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

        // 幂等校验 1：已有该成员的有效生成结果：不重复生成
        if hasTerminalQuestions(payload: target.payload, memberID: memberID) {
            return
        }
        // 幂等校验 2：已有针对该成员的活跃任务：不重复启动
        if hasActiveGeneration(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id,
            memberID: memberID
        ) {
            return
        }

        // 非新建链路（如重新进入对话时自动绑定默认成员）：只做异常修复，不生成
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

        // 同步取消旧任务并注册新任务，中间无 await，避免竞态
        cancelAll(for: threadID)
        registerGeneration(
            target: target,
            memberID: memberID,
            threadID: threadID,
            stateStore: stateStore,
            resolveModelName: resolveModelName
        )
    }

    /// 重新进入已有对话时的异常修复入口
    ///
    /// 严格遵循 CHAT-000028 需求：**绝不触发 AI 生成**，仅修复异常状态：
    /// - 已有可展示问题（generated/fallback/preset/旧版无状态 payload）：原样展示，不做任何操作
    /// - 处于 generating 状态、失败状态或问题列表为空：回写固定三条问题兜底
    ///
    /// - Parameters:
    ///   - threadID: 会话线程 ID
    ///   - messages: 当前消息列表
    ///   - stateStore: 聊天状态存储
    func repairGuideQuestionsForReenteredThread(
        threadID: UUID,
        messages: [ChatMessage],
        stateStore: ChatStateStore
    ) async {
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages) else {
            return
        }

        // 有活跃生成任务时不修复，避免覆盖即将回写的 AI 结果
        if hasActiveGeneration(
            threadID: threadID,
            messageID: target.message.clientMessageID,
            blockID: target.block.id
        ) {
            return
        }

        // 已有问题：不处理
        guard target.payload.questions.isEmpty else {
            return
        }

        // 空问题或异常状态：回写固定兜底
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

    /// 检查 payload 中是否已有该成员的可展示终态问题
    ///
    /// 终态指生成流程已结束，不会再变更：
    /// - .generated: AI 生成成功
    /// - .fallback: 生成失败，已用固定问题兜底
    ///
    /// - Parameters:
    ///   - payload: 引导卡片 payload
    ///   - memberID: 成员 ID
    /// - Returns: 已有对应成员的终态问题返回 true，否则返回 false
    private func hasTerminalQuestions(payload: ChatGuideCardPayload, memberID: Int) -> Bool {
        let state = payload.effectiveQuestionGenerationState
        return payload.questionsBelongTo(memberID: memberID)
            && (state == .generated || state == .fallback)
            && payload.questions.isEmpty == false
    }

    /// 同步注册一个新的生成任务
    ///
    /// - Important: 核心并发安全保证：
    ///   1. 注册是同步操作，与取消操作之间无 await 窗口，避免竞态
    ///   2. 任务启动后**立即**先标记为 generating 状态，再调用 AI，避免 UI 出现空窗
    ///   3. 同位置已有相同成员的活跃任务时直接返回，不重复注册
    ///   4. 同位置有旧任务时先取消并标记为"已被取代"，防止旧任务回写覆盖
    ///
    /// - Parameters:
    ///   - target: 引导卡片目标上下文
    ///   - memberID: 生成针对的成员 ID
    ///   - threadID: 会话线程 ID
    ///   - stateStore: 聊天状态存储
    ///   - resolveModelName: 模型名称解析闭包
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

        // 幂等：同位置已有相同成员的活跃任务，直接返回
        if let active = activeTasks[key], active.memberID == memberID {
            return
        }

        // 取消旧任务并标记为已被接管（同步操作，无 await）
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

        // 创建异步任务：先更新 UI 为 loading 状态，再执行实际生成
        let task = Task { [weak self] in
            guard let self else { return }
            // 第一步：标记为生成中，UI 显示 loading
            await self.markGenerating(
                token: token,
                target: target,
                stateStore: stateStore
            )
            // 第二步：执行 AI 生成流程
            await self.runGeneration(
                token: token,
                metricSections: target.payload.metricSections,
                stateStore: stateStore,
                resolveModelName: resolveModelName
            )
            // 第三步：任务结束后清理自己（仅当自己还是当前活跃任务时）
            await MainActor.run {
                self.clearActiveTaskIfMatching(key: key, taskID: taskID)
            }
        }

        // 同步注册到活跃任务表
        activeTasks[key] = ActiveGuideQuestionTask(
            memberID: memberID,
            taskID: taskID,
            startedAt: startedAt,
            task: task
        )
    }

    /// 检查指定位置是否有针对指定成员的活跃生成任务（内部重载，增加 memberID 校验）
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

    /// 仅当 taskID 匹配当前活跃任务时，才清除该任务
    /// - Note: 防止新任务启动后，旧任务完成时错误清除新任务
    private func clearActiveTaskIfMatching(key: ChatGuideQuestionTaskKey, taskID: UUID) {
        guard activeTasks[key]?.taskID == taskID else { return }
        activeTasks[key] = nil
    }

    /// 实际执行 AI 生成流程（任务体核心逻辑）
    ///
    /// 处理三种结果：
    /// 1. 生成成功：校验 token 有效性后回写 AI 生成的问题
    /// 2. 任务取消：检查是否有新任务接管，无接管则落固定问题兜底，避免永久 loading
    /// 3. 生成失败/解析失败：直接落固定问题兜底
    ///
    /// - Parameters:
    ///   - token: 生成任务令牌
    ///   - metricSections: 健康指标分组数据
    ///   - stateStore: 聊天状态存储
    ///   - resolveModelName: 模型名称解析闭包
    private func runGeneration(
        token: ChatGuideQuestionGenerationToken,
        metricSections: [ChatGuideMetricSection],
        stateStore: ChatStateStore,
        resolveModelName: @escaping (UUID) async -> String?
    ) async {
        let started = Date()
        // 解析当前线程应使用的模型
        let modelName = await resolveModelName(token.threadID)
        logger.info(
            "chat.guide.questions.generation_start thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID) model=\(modelName ?? "default")",
            module: .general
        )

        // 构建生成输入参数
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
            // 调用 UseCase 执行生成
            let output = try await generationUseCase.generate(input: input)
            logger.info(
                "chat.guide.questions.generated_ready thread=\(shortID(token.threadID)) message=\(shortID(token.messageID)) block=\(shortID(token.blockID)) tokenMember=\(token.memberID) questionCount=\(output.questions.count) ids=\(output.questions.map(\.id).joined(separator: ","))",
                module: .general
            )
            // 校验通过后回写结果
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
                // 生成结果已回写：后台异步登记问题，成功后把 server_question_id 回填到卡片（失败不阻断）。
                registerGeneratedQuestionsInBackground(
                    token: token,
                    memberID: output.memberID,
                    questions: output.questions,
                    stateStore: stateStore
                )
            }
        } catch ChatGuideQuestionGenerationUseCaseError.cancelled {
            logger.info(
                "chat.guide.questions.generation_cancelled thread=\(shortID(token.threadID)) block=\(shortID(token.blockID)) member=\(token.memberID)",
                module: .general
            )
            // 关键逻辑：任务被取消时，检查是否有新任务接管
            // - 有新任务接管：什么也不做，让新任务处理结果
            // - 无新任务接管：落固定问题兜底，避免卡片永久停留在 loading 状态
            if hasNewerGenerationTask(than: token) == false {
                await applyPreset(
                    token: token,
                    state: .preset,
                    stateStore: stateStore,
                    errorMessage: "cancelled_without_takeover"
                )
            }
        } catch {
            // 其他所有错误：统一用固定问题兜底
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

    /// 检查同一 block 上是否有比指定 token 更新的生成任务已接管
    ///
    /// 两种情况判定为被接管：
    /// 1. 该 token 已被记录在 supersededTaskIDByKey 中（曾被取消并标记取代）
    /// 2. 当前活跃任务的 taskID 与该 token 不同（已有新任务启动）
    ///
    /// - Parameter token: 待检查的任务令牌
    /// - Returns: 有更新任务接管返回 true，否则返回 false
    private func hasNewerGenerationTask(than token: ChatGuideQuestionGenerationToken) -> Bool {
        let key = ChatGuideQuestionTaskKey(
            threadID: token.threadID,
            messageID: token.messageID,
            blockID: token.blockID
        )
        // 检查是否曾被标记为已取代
        if supersededTaskIDByKey[key] == token.taskID {
            return true
        }
        // 检查当前活跃任务是否是其他任务
        guard let active = activeTasks[key] else { return false }
        return active.taskID != token.taskID
    }

    /// 取消指定 key 的活跃任务，并标记为"已被新任务取代"
    /// - Note: 调用方负责后续移除 activeTasks 条目或立即覆盖注册新任务
    private func cancelActiveTaskAndMarkSuperseded(forKey key: ChatGuideQuestionTaskKey) {
        guard let active = activeTasks[key] else { return }
        active.task.cancel()
        supersededTaskIDByKey[key] = active.taskID
    }

    /// 将引导卡片标记为"生成中"状态，UI 显示 loading
    private func markGenerating(
        token: ChatGuideQuestionGenerationToken,
        target: ChatGuideGuideCardTarget,
        stateStore: ChatStateStore
    ) async {
        var payload = target.payload
        payload.questions = []
        payload.memberId = token.memberID
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: .generating,
            source: "current_chat_ai",
            memberId: token.memberID
        )
        await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: token.threadID,
            stateStore: stateStore
        )
    }

    /// 直接对已知 target 应用固定预设问题
    /// - Parameters:
    ///   - target: 引导卡片目标上下文
    ///   - threadID: 会话线程 ID
    ///   - state: 要设置的生成状态（preset/fallback）
    ///   - stateStore: 聊天状态存储
    ///   - errorMessage: 可选的错误原因信息，用于埋点和问题排查
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
            memberId: nil,
            errorMessage: errorMessage
        )
        await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: threadID,
            stateStore: stateStore
        )
    }

    /// 通过 token 重新定位 target 后应用固定预设问题（宽容校验）
    ///
    /// 用于取消场景下的兜底：此时任务已被取消，原来的 target 可能已过期，需要重新从仓库加载最新数据
    ///
    /// - Parameters:
    ///   - token: 任务令牌
    ///   - state: 要设置的生成状态
    ///   - stateStore: 聊天状态存储
    ///   - errorMessage: 错误原因
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

    /// 应用 AI 生成成功的结果
    ///
    /// 使用 generated 阶段严格校验规则，校验通过后回写 AI 生成的问题列表和完整元数据
    ///
    /// - Parameters:
    ///   - token: 任务令牌
    ///   - output: AI 生成用例输出结果
    ///   - stateStore: 聊天状态存储
    /// - Returns: 成功应用返回 true，校验失败返回 false
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
            payload.memberId = output.memberID
            payload.questionGeneration = ChatGuideQuestionGenerationMeta(
                state: .generated,
                source: output.source,
                memberId: output.memberID,
                memberProfileDigest: output.memberProfileDigest,
                generatedAt: output.generatedAt
            )
        }
    }

    /// 后台异步登记 AI 生成问题，成功后把 server_question_id 回填到卡片（best-effort，失败不阻断主流程）。
    private func registerGeneratedQuestionsInBackground(
        token: ChatGuideQuestionGenerationToken,
        memberID: Int,
        questions: [ChatGuideQuestion],
        stateStore: ChatStateStore
    ) {
        guard let reporter = registrationReporter else {
            logger.warning(
                "[CHATGUIDE-DEBUG][coordinator] registrationReporter is nil, skip register thread=\(shortID(token.threadID))",
                module: .general
            )
            return
        }
        logger.info(
            "[CHATGUIDE-DEBUG][coordinator] register start thread=\(shortID(token.threadID)) memberID=\(memberID) count=\(questions.count) ids=\(questions.map(\.id).joined(separator: ","))",
            module: .general
        )
        Task {
            let mapping = await reporter.registerGeneratedQuestions(memberID: memberID, questions: questions)
            logger.info(
                "[CHATGUIDE-DEBUG][coordinator] register mapping=\(mapping) thread=\(shortID(token.threadID))",
                module: .general
            )
            guard mapping.isEmpty == false else {
                logger.warning(
                    "[CHATGUIDE-DEBUG][coordinator] register mapping empty, skip backfill thread=\(shortID(token.threadID))",
                    module: .general
                )
                return
            }
            await persistServerQuestionIDs(mapping, token: token, stateStore: stateStore)
        }
    }

    /// 把登记返回的 clientQuestionID → serverQuestionID 映射回填到当前引导卡片（不经过 token 校验，做防御性校验后直接持久化）。
    private func persistServerQuestionIDs(
        _ mapping: [String: Int],
        token: ChatGuideQuestionGenerationToken,
        stateStore: ChatStateStore
    ) async {
        guard await chatRepository.loadThread(id: token.threadID) != nil else {
            logger.warning(
                "[CHATGUIDE-DEBUG][coordinator] persist skip: thread missing thread=\(shortID(token.threadID))",
                module: .general
            )
            return
        }
        let messages = await chatRepository.loadMessages(threadID: token.threadID, limit: 50, before: nil)
        guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: messages),
              target.message.clientMessageID == token.messageID,
              target.block.id == token.blockID else {
            logger.warning(
                "[CHATGUIDE-DEBUG][coordinator] persist skip: guide card not found thread=\(shortID(token.threadID))",
                module: .general
            )
            return
        }
        // 仅当卡片仍停留在本次生成的终态时才回填，避免覆盖更新的结果。
        guard target.payload.effectiveQuestionGenerationState == .generated,
              target.payload.questionGeneration?.memberId == token.memberID else {
            logger.warning(
                "[CHATGUIDE-DEBUG][coordinator] persist skip: state/member mismatch thread=\(shortID(token.threadID)) state=\(target.payload.effectiveQuestionGenerationState.rawValue) payloadMember=\(target.payload.questionGeneration?.memberId.map(String.init) ?? "nil") tokenMember=\(token.memberID)",
                module: .general
            )
            return
        }

        var payload = target.payload
        var changed = false
        for index in payload.questions.indices {
            guard let serverID = mapping[payload.questions[index].id],
                  payload.questions[index].serverQuestionId != serverID else { continue }
            logger.info(
                "[CHATGUIDE-DEBUG][coordinator] persist backfill questionId=\(payload.questions[index].id) serverId=\(serverID)",
                module: .general
            )
            payload.questions[index].serverQuestionId = serverID
            changed = true
        }
        guard changed else {
            logger.info(
                "[CHATGUIDE-DEBUG][coordinator] persist skip: no changed server ids thread=\(shortID(token.threadID))",
                module: .general
            )
            return
        }
        let didPersist = await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: token.threadID,
            stateStore: stateStore
        )
        logger.info(
            "[CHATGUIDE-DEBUG][coordinator] persist done thread=\(shortID(token.threadID)) didPersist=\(didPersist)",
            module: .general
        )
    }

    /// 应用生成失败的兜底结果：写入固定预设问题
    ///
    /// 使用 fallback 阶段宽容校验规则，尽可能修复异常状态
    ///
    /// - Parameters:
    ///   - token: 任务令牌
    ///   - errorCategory: 错误分类，用于埋点
    ///   - stateStore: 聊天状态存储
    /// - Returns: 成功应用返回 true，校验失败返回 false
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
                memberId: token.memberID,
                errorMessage: errorCategory
            )
        }
    }

    /// 更新引导卡片 payload 的通用模板方法
    ///
    /// 统一处理 token 校验，校验通过后调用 mutate 闭包修改 payload，最后持久化更新
    ///
    /// - Parameters:
    ///   - token: 任务令牌
    ///   - phase: 校验阶段（generated 严格 / fallback 宽容）
    ///   - stateStore: 聊天状态存储
    ///   - mutate: payload 修改闭包
    /// - Returns: 更新成功返回 true，校验失败或持久化失败返回 false
    @discardableResult
    private func updateGuideBlock(
        token: ChatGuideQuestionGenerationToken,
        phase: GuideTokenValidationPhase,
        stateStore: ChatStateStore,
        mutate: (inout ChatGuideCardPayload) -> Void
    ) async -> Bool {
        // 执行 token 有效性校验
        let validation = await validateToken(token, phase: phase)
        if let failure = validation.failure {
            logger.info(
                "chat.guide.questions.validate_failed phase=\(phase.rawValue) reason=\(failure.rawValue) thread=\(shortID(token.threadID)) message=\(shortID(token.messageID)) block=\(shortID(token.blockID)) tokenMember=\(token.memberID) threadMember=\(validation.threadMemberID.map(String.init) ?? "nil") payloadMember=\(validation.payloadMemberID.map(String.init) ?? "nil") state=\(validation.payloadState?.rawValue ?? "nil") questionsCount=\(validation.questionsCount)",
                module: .general
            )
            return false
        }

        guard let target = validation.target else { return false }

        // 校验通过，修改 payload
        var payload = target.payload
        mutate(&payload)
        // 持久化更新
        return await persistPayloadUpdate(
            target: target,
            payload: payload,
            threadID: token.threadID,
            stateStore: stateStore
        )
    }

    /// 持久化 payload 更新到仓库并刷新 UI 状态
    ///
    /// 两步操作：
    /// 1. 更新消息 block 到本地仓库，标记为待同步
    /// 2. 更新内存中的 stateStore，触发 UI 刷新
    ///
    /// - Parameters:
    ///   - target: 引导卡片目标上下文
    ///   - payload: 修改后的新 payload
    ///   - threadID: 会话线程 ID
    ///   - stateStore: 聊天状态存储
    /// - Returns: 持久化成功返回 true，失败返回 false
    @discardableResult
    private func persistPayloadUpdate(
        target: ChatGuideGuideCardTarget,
        payload: ChatGuideCardPayload,
        threadID: UUID,
        stateStore: ChatStateStore
    ) async -> Bool {
        // 替换 block payload，更新 revision
        let updatedBlock = target.block.replacingPayload(.chatGuideCard(payload), status: .ready)
        let state = payload.effectiveQuestionGenerationState
        logger.info(
            "chat.guide.questions.persist_attempt thread=\(shortID(threadID)) message=\(shortID(target.message.clientMessageID)) block=\(shortID(target.block.id)) state=\(state.rawValue) member=\(payload.questionGeneration?.memberId.map(String.init) ?? "nil") questionsCount=\(payload.questions.count) oldRevision=\(target.block.revision) newRevision=\(updatedBlock.revision) markPendingForSync=true",
            module: .general
        )
        // 写入本地仓库
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

        // 更新内存状态，触发 UI 刷新
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

    /// Token 校验阶段：不同阶段使用不同严格度的校验规则
    private enum GuideTokenValidationPhase: String {
        /// AI 成功结果回写阶段：使用严格校验规则
        /// - 正常情况必须严格匹配成员 ID
        /// - 特殊兼容：允许修复历史 bug 导致的 generating 状态空卡片缺失 memberID 的情况
        case generated
        /// 失败兜底回写阶段：使用宽容校验规则，尽可能修复异常状态
        case fallback
    }

    /// Token 校验失败原因枚举
    private enum GuideTokenValidationFailure: String {
        /// 线程不存在
        case threadNotFound
        /// 线程当前绑定成员与 token 中成员不匹配（成员已切换）
        case threadMemberMismatch
        /// 找不到对应的引导卡片（消息/block 已被删除或位置变化）
        case targetNotFound
        /// 已有更新的生成结果存在（任务过期）
        case newerResultExists
        /// payload 中记录的成员 ID 与 token 不匹配
        case payloadMemberMismatch
        /// fallback 阶段目标状态不可修复（已有其他成员的有效结果）
        case fallbackTargetNotRepairable
    }

    /// Token 校验结果结构体
    private struct GuideTokenValidationResult {
        /// 校验失败原因，为 nil 表示校验通过
        var failure: GuideTokenValidationFailure?
        /// 校验通过时返回定位到的引导卡片目标
        var target: ChatGuideGuideCardTarget?
        /// 线程当前绑定的成员 ID
        var threadMemberID: Int?
        /// payload 中记录的成员 ID
        var payloadMemberID: Int?
        /// payload 当前的生成状态
        var payloadState: ChatGuideQuestionGenerationState?
        /// 当前问题数量
        var questionsCount: Int = 0
    }

    /// 校验任务令牌是否有效，防止过期任务回写覆盖新结果
    ///
    /// **generated 阶段（严格）校验规则（CHAT-000028 3.4）：**
    /// 1. 线程必须存在
    /// 2. 线程当前绑定成员必须等于 token.memberID（成员切换硬校验）
    /// 3. 对应消息和 block 必须存在且匹配
    /// 4. 不存在比当前任务更新的已完成结果
    /// 5. payload 中成员 ID 匹配，或（payload 成员 ID 为空 + 状态为 generating + 问题为空）允许兼容修复
    ///
    /// **fallback 阶段（宽容）校验规则：**
    /// - 只要不是其他成员的有效结果，都尽可能允许修复
    ///
    /// - Parameters:
    ///   - token: 待校验的任务令牌
    ///   - phase: 校验阶段
    /// - Returns: 校验结果，包含失败原因或定位到的目标
    private func validateToken(
        _ token: ChatGuideQuestionGenerationToken,
        phase: GuideTokenValidationPhase
    ) async -> GuideTokenValidationResult {
        // 1. 校验线程存在
        guard let thread = await chatRepository.loadThread(id: token.threadID) else {
            return GuideTokenValidationResult(failure: .threadNotFound, target: nil, threadMemberID: nil, payloadMemberID: nil, payloadState: nil)
        }
        // 2. 硬校验：线程当前成员必须与 token 一致（防止成员切换后旧任务回写）
        guard thread.memberID == token.memberID else {
            return GuideTokenValidationResult(
                failure: .threadMemberMismatch,
                target: nil,
                threadMemberID: thread.memberID,
                payloadMemberID: nil,
                payloadState: nil
            )
        }

        // 3. 校验引导卡片存在且位置匹配
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

        let payloadMemberID = target.payload.questionGeneration?.memberId
        let state = target.payload.effectiveQuestionGenerationState
        var result = GuideTokenValidationResult(
            failure: nil,
            target: target,
            threadMemberID: thread.memberID,
            payloadMemberID: payloadMemberID,
            payloadState: state,
            questionsCount: target.payload.questions.count
        )

        // generated 阶段：严格校验
        if phase == .generated {
            // 已有同成员更新的终态结果：当前任务已过期，拦截
            if state == .generated || state == .fallback,
               let generatedAt = target.payload.questionGeneration?.generatedAt,
               generatedAt > token.startedAt,
               payloadMemberID == token.memberID {
                result.failure = .newerResultExists
                return result
            }
            // 成员 ID 匹配：校验通过
            if payloadMemberID == token.memberID {
                return result
            }
            // 兼容历史 bug：生成中状态的空卡片缺失 memberID，允许回写并补齐
            if payloadMemberID == nil,
               state == .generating,
               target.payload.questions.isEmpty {
                return result
            }
            // 其他情况：成员不匹配，拦截
            result.failure = .payloadMemberMismatch
            return result
        }

        // fallback 阶段：宽容校验，尽可能修复异常
        // 成员 ID 匹配：允许
        if payloadMemberID == token.memberID {
            return result
        }
        // 无成员 ID + 生成中/空问题：允许修复
        if payloadMemberID == nil,
           state == .generating || target.payload.questions.isEmpty {
            return result
        }
        // 完全没有生成元数据 + 空问题：允许修复
        if target.payload.questionGeneration == nil,
           target.payload.questions.isEmpty {
            return result
        }
        // 其他情况（已有其他成员的有效结果）：不可修复
        result.failure = .fallbackTargetNotRepairable
        return result
    }

    /// 将错误转换为分类字符串，用于日志埋点
    /// - Parameter error: 原始错误
    /// - Returns: 错误分类标识字符串
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

    /// 生成 UUID 的短标识符（前 8 位），用于日志输出，降低日志长度
    /// - Parameter id: 完整 UUID
    /// - Returns: 8 位短 ID 字符串
    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
