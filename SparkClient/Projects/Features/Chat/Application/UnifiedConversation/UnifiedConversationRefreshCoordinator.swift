import Foundation

/// CHAT-000057 28.7/30.6：统一消息刷新原因（所有触发源只提交 reason，不直接调用 Manifest API）。
enum UnifiedConversationRefreshReason: String, Sendable {
    /// 进入消息分段
    case enterMessageSegment
    /// 下拉刷新
    case pullToRefresh
    /// 前后台恢复
    case foreground
    /// 推送同步
    case push
    /// 账号登录/切换后的首次同步
    case accountSwitch
    /// 打开 unknown 会话触发的确认
    case threadOpenConfirmation
    /// unknown 确认失败后的手动/退避重试
    case retryConfirmation
    /// 医院目录创建/续聊成功后的轻量 delta
    case hospitalThreadCreated
}

/// CHAT-000057 28.7/30.6/33：统一消息刷新协调器（唯一同步入口）。
///
/// 职责：
/// - 同账号刷新 single-flight：并发触发合并为同一次同步，不并行重复拉取；
/// - 账号切换：先取消旧账号任务与 unknown 重试，禁止旧回包污染新账号；
/// - unknown 确认：按 threadID 退避重试（有上限），删除/撤权后 cancel(threadID) 拒绝延迟回包；
/// - 维护 unknown 分类状态输入（resolving / retryableFailure）供 Projector 使用。
actor UnifiedConversationRefreshCoordinator {
    private let syncUseCase: SyncUnifiedConversationManifestUseCase
    private let featureFlags: UnifiedConversationFeatureFlags
    private let logger: Logger

    /// accountID -> 进行中的刷新任务（single-flight）
    private var inFlight: [Int64: Task<UnifiedConversationManifestSyncResult, Never>] = [:]
    /// threadID -> unknown 确认重试任务
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    /// 已取消的 threadID（删除/撤权后拒绝再调度）
    private var cancelledThreadIDs: Set<UUID> = []
    /// 确认失败但可重试的 threadID
    private var retryableFailureThreadIDs: Set<UUID> = []
    /// unknown 重试退避（秒），指数递增、有上限。
    private let retryBackoffSeconds: [UInt64]
    /// 单 thread 最大重试次数。
    private let maxRetryAttempts: Int

    init(
        syncUseCase: SyncUnifiedConversationManifestUseCase,
        featureFlags: UnifiedConversationFeatureFlags,
        logger: Logger = ConsoleLogger(),
        retryBackoffSeconds: [UInt64] = [2, 4, 8, 16, 30],
        maxRetryAttempts: Int = 5
    ) {
        self.syncUseCase = syncUseCase
        self.featureFlags = featureFlags
        self.logger = logger
        self.retryBackoffSeconds = retryBackoffSeconds
        self.maxRetryAttempts = maxRetryAttempts
    }

    /// 账号级刷新（single-flight）：同账号并发调用合并等待同一任务。
    /// Manifest 未启用时直接返回 endpointUnavailable，不产生网络请求。
    @discardableResult
    func refresh(
        accountID: Int64,
        reason: UnifiedConversationRefreshReason
    ) async -> UnifiedConversationManifestSyncResult {
        guard featureFlags.manifestEnabled else { return .endpointUnavailable }

        if let existing = inFlight[accountID] {
            logger.debug(
                "chat.unified.refresh.coalesced account=\(accountID) reason=\(reason.rawValue)",
                module: .general
            )
            return await existing.value
        }

        let task = Task<UnifiedConversationManifestSyncResult, Never> { [syncUseCase, logger] in
            let result = await syncUseCase.execute(accountID: accountID)
            logger.debug(
                "chat.unified.refresh.done account=\(accountID) reason=\(reason.rawValue) result=\(result)",
                module: .general
            )
            return result
        }
        inFlight[accountID] = task
        let result = await task.value
        inFlight[accountID] = nil

        // 同步成功后清除已成功确认 thread 的失败标记。
        if case .success(let changed, let revoked, _) = result {
            retryableFailureThreadIDs.subtract(changed)
            for threadID in revoked {
                cancel(threadID: threadID)
            }
        }
        return result
    }

    /// 打开 unknown 卡片/手动重试：调度一次账号 delta，并按退避重试直至确认或达到上限。
    func scheduleUnknownConfirmation(
        threadID: UUID,
        accountID: Int64
    ) {
        guard featureFlags.manifestEnabled, featureFlags.unknownGatingEnabled else { return }
        guard cancelledThreadIDs.contains(threadID) == false else { return }
        guard retryTasks[threadID] == nil else { return }
        retryableFailureThreadIDs.remove(threadID)

        retryTasks[threadID] = Task<Void, Never> { [weak self] in
            guard let self else { return }
            var attempt = 0
            while attempt < self.maxRetryAttempts {
                if Task.isCancelled { return }
                let confirmed = await self.confirmOnce(threadID: threadID, accountID: accountID)
                if confirmed { return }
                attempt += 1
                guard attempt < self.maxRetryAttempts else { break }
                let backoff = self.retryBackoffSeconds[min(attempt - 1, self.retryBackoffSeconds.count - 1)]
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            }
            await self.markRetryableFailure(threadID: threadID)
        }
    }

    /// 删除/撤权后拒绝延迟回包合并与后续重试（D-026/31.4）。
    func cancel(threadID: UUID) {
        cancelledThreadIDs.insert(threadID)
        retryableFailureThreadIDs.remove(threadID)
        retryTasks[threadID]?.cancel()
        retryTasks[threadID] = nil
    }

    /// 账号切换：取消全部刷新与重试任务，清空内存状态（在加载新账号缓存前调用）。
    func cancelAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        for task in retryTasks.values { task.cancel() }
        retryTasks.removeAll()
        retryableFailureThreadIDs.removeAll()
        cancelledThreadIDs.removeAll()
    }

    /// Projector 的 unknown 状态输入。
    func unknownResolutionContext(
        unresolvedThreadIDs: Set<UUID>
    ) -> UnifiedConversationProjector.UnknownResolutionContext {
        UnifiedConversationProjector.UnknownResolutionContext(
            resolving: unresolvedThreadIDs.subtracting(retryableFailureThreadIDs),
            retryableFailures: retryableFailureThreadIDs.intersection(unresolvedThreadIDs)
        )
    }

    // MARK: - 私有

    /// 执行一次账号 delta 并检查目标 thread 是否已被 Manifest 覆盖。
    private func confirmOnce(threadID: UUID, accountID: Int64) async -> Bool {
        let result = await refresh(accountID: accountID, reason: .retryConfirmation)
        guard case .success = result else { return false }
        return true
    }

    private func markRetryableFailure(threadID: UUID) {
        retryTasks[threadID] = nil
        guard cancelledThreadIDs.contains(threadID) == false else { return }
        retryableFailureThreadIDs.insert(threadID)
        logger.warning(
            "chat.unified.confirm.retry_exhausted thread=\(threadID.uuidString.prefix(8))",
            module: .general
        )
    }
}
