import Combine
import Foundation

@MainActor
final class SubscriptionSyncCoordinator: ObservableObject {
    enum IdentityState: Equatable {
        case unbound
        case binding
        case bound(accountID: Int64)
        case failed(accountID: Int64, message: String)
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case pendingRetry
        case failed(message: String)
    }

    enum Reason: String {
        case sessionRestored
        case foreground
        case purchaseCompleted
        case restoreCompleted
        case manualRefresh
    }

    @Published private(set) var identityState: IdentityState = .unbound
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var latestSummary: SparkSubscriptionAPI.Summary?

    private let api: SparkSubscriptionAPI
    private let sessionStore: AppSessionStore
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger
    private let summaryStore: SubscriptionSummaryStore
    private var activeSyncTask: Task<Void, Never>?
    private var lastAttemptAt: Date?
    private var boundAccountID: Int64?
    private let minimumInterval: TimeInterval = 300

    init(
        api: SparkSubscriptionAPI,
        sessionStore: AppSessionStore,
        aiConfigCenter: AIConfigCenter,
        logger: Logger,
        summaryStore: SubscriptionSummaryStore = SubscriptionSummaryStore()
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.aiConfigCenter = aiConfigCenter
        self.logger = logger
        self.summaryStore = summaryStore
    }

    var canPurchaseOrRestore: Bool {
        if case .bound = identityState { return true }
        return false
    }

    func beginBinding(accountID: Int64) {
        if let previousAccountID = boundAccountID, previousAccountID != accountID {
            summaryStore.remove(accountID: previousAccountID)
        }
        activeSyncTask?.cancel()
        activeSyncTask = nil
        latestSummary = nil
        boundAccountID = nil
        identityState = .binding
        syncState = .idle
        logger.debug("订阅：开始 RevenueCat 身份绑定 accountID=\(accountID)", module: .auth)
    }

    func markBound(accountID: Int64) {
        boundAccountID = accountID
        identityState = .bound(accountID: accountID)
        latestSummary = summaryStore.load(accountID: accountID)
        logger.info("订阅：RevenueCat 身份绑定成功 accountID=\(accountID)", module: .auth)
    }

    func markBindingFailed(accountID: Int64, error: Error) {
        identityState = .failed(accountID: accountID, message: error.localizedDescription)
        syncState = .failed(message: error.localizedDescription)
        logger.warning("订阅：RevenueCat 身份绑定失败 accountID=\(accountID) error=\(error.localizedDescription)", module: .auth)
    }

    func reset() {
        if let accountID = boundAccountID {
            summaryStore.remove(accountID: accountID)
        }
        activeSyncTask?.cancel()
        activeSyncTask = nil
        identityState = .unbound
        syncState = .idle
        lastAttemptAt = nil
        latestSummary = nil
        boundAccountID = nil
    }

    func synchronizeIfAllowed(reason: Reason, force: Bool = false) {
        guard canPurchaseOrRestore else { return }
        guard activeSyncTask == nil else { return }
        if !force, let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < minimumInterval {
            return
        }
        lastAttemptAt = Date()
        guard case .bound(let requestedAccountID) = identityState else { return }
        syncState = .syncing
        activeSyncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.activeSyncTask = nil }
            do {
                let summary = try await self.api.synchronize()
                guard !Task.isCancelled else { return }
                self.apply(summary, requestedAccountID: requestedAccountID)
                await self.aiConfigCenter.refreshRemoteConfig()
                self.syncState = summary.syncState == "pending_retry" ? .pendingRetry : .idle
                self.logger.info(
                    "订阅：服务端同步完成 reason=\(reason.rawValue) isPro=\(summary.isPro)，AI 配置已刷新",
                    module: .auth
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.syncState = .pendingRetry
                self.logger.warning("订阅：服务端同步失败 reason=\(reason.rawValue) error=\(error.localizedDescription)", module: .auth)
            }
        }
    }

    func retryBinding(accountID: Int64) {
        beginBinding(accountID: accountID)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await RevenueCatClient.shared.identify(accountID: accountID)
                self.markBound(accountID: accountID)
                self.synchronizeIfAllowed(reason: .manualRefresh, force: true)
            } catch {
                self.markBindingFailed(accountID: accountID, error: error)
            }
        }
    }

    private func apply(_ summary: SparkSubscriptionAPI.Summary, requestedAccountID: Int64) {
        guard boundAccountID == requestedAccountID,
              case .bound(let currentBoundAccountID) = identityState,
              currentBoundAccountID == requestedAccountID,
              case .signedIn(let session) = sessionStore.state,
              session.accountID == requestedAccountID else {
            logger.warning(
                "订阅：同步结果无法写入当前 Session，当前状态=\(sessionStore.state)，isPro=\(summary.isPro)",
                module: .auth
            )
            return
        }
        latestSummary = summary
        summaryStore.save(summary, accountID: requestedAccountID)
        logger.info(
            "订阅：写入当前 Session accountID=\(session.accountID) isPro=\(session.isPro) -> \(summary.isPro)",
            module: .auth
        )
        sessionStore.replaceCurrentSession(session.replacing(isPro: summary.isPro))
    }
}
