import Foundation

/// CHAT-000056 Q3：全局补偿触发源。四个生命周期事件统一进入同一个账号级全局增量补偿入口。
nonisolated enum ChatGlobalCompensationSource: String, Sendable {
    /// v1 事件或无法解析 thread 的 v2 事件——不猜当前会话，走全局补偿。
    case realtimeHint
    /// WebSocket 每次连接成功（含首次与每次重连）。
    case realtimeConnected
    /// 账号启动（账号准备完成）。
    case accountStartup
    /// App 从非活跃状态恢复前台。
    case foreground
    /// 网络从不可用恢复为可用。
    case networkRecovered
}

/// CHAT-000056：实时拉取调度器。
///
/// 收口 WebSocket hint 与四个生命周期触发源：
/// - per-thread 状态机：`idle → scheduled(合并窗口) → pulling → (dirty 重拉 | retryWaiting → pulling)`；
/// - 全局补偿状态机：`globalIdle → globalPulling → (globalDirty 再执行一次)`；
/// - 全局运行期间到达的 thread hint 留下记录，全局完成后补一次 thread 定向拉取，避免事件被吞。
///
/// 网络请求与入库由注入的闭包完成（`ChatSyncEngine`），调度器只维护并发与时序语义，因此可独立单测。
actor ChatRealtimePullScheduler {
    /// Q9 拉取失败分类。
    nonisolated enum PullErrorClassification: Sendable {
        /// 网络断开、超时、5xx：保留 cursor，有限退避重试，thread 保持 dirty。
        case retryable
        /// 服务端明确 cursor 无效/过期：只清该 thread cursor，从首屏重拉，不删除本地历史。
        case cursorInvalid
        /// thread 404 / 无效：结束该 thread 的自动重试。
        case threadMissing
        /// 其他（鉴权、撤权、解码错误等）：不自动重试，按既有流程处理。
        case terminal
    }

    struct Config: Sendable {
        /// 同一主运行循环内到达的 hint 合并窗口（Q4：约 200–300ms）。
        var debounceNanoseconds: UInt64
        /// 每个 thread 自动重试次数上限；达到上限后保持 dirty，等待下一次触发。
        var maxRetryAttempts: Int
        /// 退避起始间隔，按 2 的幂递增。
        var retryBaseDelayNanoseconds: UInt64
        /// 退避间隔上限。
        var retryMaxDelayNanoseconds: UInt64
        /// 单次全局补偿内 dirty 追加轮次上限，避免触发风暴下无限循环。
        var maxGlobalExtraCycles: Int

        static let `default` = Config(
            debounceNanoseconds: 250_000_000,
            maxRetryAttempts: 3,
            retryBaseDelayNanoseconds: 1_000_000_000,
            retryMaxDelayNanoseconds: 30_000_000_000,
            maxGlobalExtraCycles: 3
        )
    }

    /// (threadID, forceFullRefresh) — forceFullRefresh=true 时先清除该 thread cursor 再从首屏拉取。
    typealias ThreadPullHandler = @Sendable (UUID, Bool) async throws -> Void
    typealias GlobalPullHandler = @Sendable () async throws -> Void
    typealias ErrorClassifier = @Sendable (Error) -> PullErrorClassification

    private enum PendingKind: Sendable {
        case debounce
        case retry
    }

    private struct ThreadState {
        var isPulling = false
        var dirty = false
        var retryAttempt = 0
        var pendingKind: PendingKind?
        var pendingTask: Task<Void, Never>?
    }

    private let config: Config
    private let pullThread: ThreadPullHandler
    private let pullGlobal: GlobalPullHandler
    private let classifyError: ErrorClassifier
    private let logger: Logger

    private var threadStates: [UUID: ThreadState] = [:]
    private var globalRunning = false
    private var globalDirty = false
    private var hintedThreadsDuringGlobal: Set<UUID> = []
    /// 账号 generation：账号切换/登出时递增，迟到任务只准完成网络请求，不得再改调度状态。
    private var epoch: UInt64 = 0

    init(
        config: Config = .default,
        pullThread: @escaping ThreadPullHandler,
        pullGlobal: @escaping GlobalPullHandler,
        classifyError: @escaping ErrorClassifier,
        logger: Logger = ConsoleLogger()
    ) {
        self.config = config
        self.pullThread = pullThread
        self.pullGlobal = pullGlobal
        self.classifyError = classifyError
        self.logger = logger
    }

    // MARK: - 入口

    /// 收到结构化实时 hint。v1 / 无 thread 的事件走全局补偿；否则按 thread 定向拉取。
    func handleHint(_ hint: ChatSyncHint) {
        if let emittedAt = hint.emittedAt {
            let lagMilliseconds = Int(Date().timeIntervalSince(emittedAt) * 1000)
            logger.debug(
                "chat.realtime.hint version=\(hint.payloadVersion) thread=\(hint.threadID.map(shortID) ?? "-") lag_ms=\(lagMilliseconds) messages=\(hint.messageIDs.count)",
                module: .general
            )
        }
        guard let threadID = hint.threadID else {
            requestGlobalCompensation(source: .realtimeHint)
            return
        }
        if globalRunning {
            hintedThreadsDuringGlobal.insert(threadID)
            return
        }
        scheduleThreadPull(threadID, currentEpoch: epoch)
    }

    /// Q3：账号启动、连接成功、前台恢复、网络恢复统一入口；single-flight + dirty 合并。
    func requestGlobalCompensation(source: ChatGlobalCompensationSource) {
        if globalRunning {
            globalDirty = true
            logger.debug("chat.realtime.global dirty source=\(source.rawValue)", module: .general)
            return
        }
        globalRunning = true
        globalDirty = false
        let expectedEpoch = epoch
        logger.info("chat.realtime.global start source=\(source.rawValue)", module: .general)
        Task { [weak self] in
            await self?.runGlobalLoop(expectedEpoch: expectedEpoch)
        }
    }

    /// 账号切换/登出：取消待执行任务；进行中的网络请求允许完成，但 epoch 变化后不再触碰调度状态。
    func cancelAll() {
        epoch &+= 1
        for (_, state) in threadStates {
            state.pendingTask?.cancel()
        }
        threadStates.removeAll()
        hintedThreadsDuringGlobal.removeAll()
        globalDirty = false
    }

    // MARK: - per-thread 调度

    private func scheduleThreadPull(_ threadID: UUID, currentEpoch: UInt64) {
        var state = threadStates[threadID] ?? ThreadState()
        if state.isPulling {
            // pulling 期间到达的同 thread hint 只标 dirty，不新开并行请求。
            state.dirty = true
            threadStates[threadID] = state
            return
        }
        if state.pendingKind == .debounce {
            // 合并窗口内的 hint 合并为一次请求。
            return
        }
        if state.pendingKind == .retry {
            // 新 hint 优先于退避重试：取消退避，走正常合并窗口尽快拉取。
            state.pendingTask?.cancel()
            state.pendingTask = nil
            state.pendingKind = nil
        }
        let debounce = config.debounceNanoseconds
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard Task.isCancelled == false else { return }
            await self?.startScheduledThreadPull(threadID, expectedEpoch: currentEpoch)
        }
        state.pendingKind = .debounce
        state.pendingTask = task
        threadStates[threadID] = state
    }

    private func startScheduledThreadPull(_ threadID: UUID, expectedEpoch: UInt64) async {
        guard epoch == expectedEpoch else { return }
        guard var state = threadStates[threadID], state.isPulling == false else { return }
        state.pendingTask = nil
        state.pendingKind = nil
        state.isPulling = true
        state.dirty = false
        threadStates[threadID] = state
        await runThreadPullLoop(threadID, forceFullFirst: false, expectedEpoch: expectedEpoch)
    }

    /// 单 thread 拉取循环：成功且 dirty → 立即补拉；cursor 失效 → 清 cursor 全量重拉；可重试失败 → 退避。
    private func runThreadPullLoop(_ threadID: UUID, forceFullFirst: Bool, expectedEpoch: UInt64) async {
        var forceFull = forceFullFirst
        while true {
            guard epoch == expectedEpoch else { return }
            do {
                try await pullThread(threadID, forceFull)
                forceFull = false
            } catch {
                let classification = classifyError(error)
                if classification == .cursorInvalid {
                    guard epoch == expectedEpoch else { return }
                    guard var state = threadStates[threadID] else { return }
                    state.retryAttempt += 1
                    threadStates[threadID] = state
                    logger.warning(
                        "chat.realtime.pull cursor_invalid thread=\(shortID(threadID)) attempt=\(state.retryAttempt)",
                        module: .general
                    )
                    guard state.retryAttempt <= config.maxRetryAttempts else {
                        keepDirtyAndStop(threadID, expectedEpoch: expectedEpoch, reason: "cursor_invalid_exhausted")
                        return
                    }
                    // Q9：仅重置该 thread，从首屏安全重拉；消息按 ID 幂等合并。
                    forceFull = true
                    continue
                }
                await handleThreadPullError(threadID, classification: classification, error: error, expectedEpoch: expectedEpoch)
                return
            }
            guard epoch == expectedEpoch else { return }
            guard var state = threadStates[threadID] else { return }
            state.retryAttempt = 0
            if state.dirty {
                // dirty 重拉：清除标记并立即补拉一次，直到没有 dirty 事件。
                state.dirty = false
                threadStates[threadID] = state
                continue
            }
            state.isPulling = false
            state.pendingTask = nil
            state.pendingKind = nil
            threadStates[threadID] = nil
            return
        }
    }

    private func handleThreadPullError(
        _ threadID: UUID,
        classification: PullErrorClassification,
        error: Error,
        expectedEpoch: UInt64
    ) async {
        guard epoch == expectedEpoch else { return }
        guard var state = threadStates[threadID] else { return }
        switch classification {
        case .retryable:
            state.retryAttempt += 1
            let attempt = state.retryAttempt
            guard attempt <= config.maxRetryAttempts else {
                keepDirtyAndStop(threadID, expectedEpoch: expectedEpoch, reason: "retry_exhausted")
                return
            }
            threadStates[threadID] = state
            let delay = retryDelay(attempt: attempt)
            logger.info(
                "chat.realtime.pull retry_scheduled thread=\(shortID(threadID)) attempt=\(attempt) delay_ms=\(delay / 1_000_000)",
                module: .general
            )
            let task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard Task.isCancelled == false else { return }
                await self?.retryThreadPullNow(threadID, expectedEpoch: expectedEpoch)
            }
            state.pendingKind = .retry
            state.pendingTask = task
            state.isPulling = false
            // 保持 dirty：后续 hint / 全局补偿可提前合并触发。
            state.dirty = true
            threadStates[threadID] = state
        case .threadMissing:
            threadStates[threadID] = nil
            logger.info(
                "chat.realtime.pull thread_missing thread=\(shortID(threadID))，结束该会话自动重试",
                module: .general
            )
        case .terminal:
            state.isPulling = false
            state.pendingTask = nil
            state.pendingKind = nil
            threadStates[threadID] = state
            logger.warning(
                "chat.realtime.pull terminal_error thread=\(shortID(threadID)) error=\(error.localizedDescription)",
                module: .general
            )
        case .cursorInvalid:
            // cursorInvalid 已在 runThreadPullLoop 内处理。
            break
        }
    }

    /// 达到重试上限：不弹全局错误、不影响其他会话；保持 dirty，等待下一次 hint / 生命周期触发。
    private func keepDirtyAndStop(_ threadID: UUID, expectedEpoch: UInt64, reason: String) {
        guard epoch == expectedEpoch else { return }
        guard var state = threadStates[threadID] else { return }
        state.isPulling = false
        state.pendingTask = nil
        state.pendingKind = nil
        state.dirty = true
        threadStates[threadID] = state
        logger.warning(
            "chat.realtime.pull \(reason) thread=\(shortID(threadID))，等待下一次触发",
            module: .general
        )
    }

    private func retryThreadPullNow(_ threadID: UUID, expectedEpoch: UInt64) async {
        guard epoch == expectedEpoch else { return }
        guard var state = threadStates[threadID], state.isPulling == false else { return }
        state.pendingTask = nil
        state.pendingKind = nil
        state.isPulling = true
        state.dirty = false
        threadStates[threadID] = state
        await runThreadPullLoop(threadID, forceFullFirst: false, expectedEpoch: expectedEpoch)
    }

    private func retryDelay(attempt: Int) -> UInt64 {
        let exponential = config.retryBaseDelayNanoseconds * UInt64(1 << max(0, attempt - 1))
        return min(config.retryMaxDelayNanoseconds, exponential)
    }

    // MARK: - 全局补偿

    private func runGlobalLoop(expectedEpoch: UInt64) async {
        var extraCycles = 0
        while true {
            do {
                try await pullGlobal()
            } catch {
                logger.warning(
                    "chat.realtime.global failed error=\(error.localizedDescription)",
                    module: .general
                )
                break
            }
            guard epoch == expectedEpoch else { return }
            if globalDirty, extraCycles < config.maxGlobalExtraCycles {
                globalDirty = false
                extraCycles += 1
                continue
            }
            break
        }
        guard epoch == expectedEpoch else { return }
        globalRunning = false
        globalDirty = false
        // 全局运行期间到达的 thread hint 无法证明已被覆盖，逐个补一次定向拉取。
        let pending = hintedThreadsDuringGlobal
        hintedThreadsDuringGlobal.removeAll()
        for threadID in pending.sorted(by: { $0.uuidString < $1.uuidString }) {
            scheduleThreadPull(threadID, currentEpoch: expectedEpoch)
        }
    }

    // MARK: - 工具

    private nonisolated func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
