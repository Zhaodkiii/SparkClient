import Foundation

/// 账号运行时：统一管理账号级内存状态和缓存失效。
///
/// 新项目只保留这一条账号切换路径，避免 UI、Bootstrapper、Container 各自手动 reset。
@MainActor
final class AccountSessionRuntime {
    private enum Mode: Equatable {
        case guest
        case account(Int64)
    }

    private let routeCoordinator: RouteCoordinator
    private let storageRegistry: StorageRegistry
    private let memberContextStore: MemberContextStore
    private let chatStateStore: ChatStateStore
    private let chatListViewModel: ChatListViewModel
    private let chatSyncSupervisor: ChatSyncSupervisor
    private let knowledgeViewModel: KnowledgeLibraryViewModel
    private let knowledgeSyncSupervisor: KnowledgeSyncSupervisor
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger
    private let clearSessionScopedViewModels: () -> Void
    private let clearExternalMedicalImport: () -> Void
    private let chatSyncSupervisorForResume: ChatSyncSupervisor?
    private var mode: Mode?
    private(set) var isAccountSwitchInProgress = false
    private var suspendedAccountIDForSwitch: Int64?

    init(
        routeCoordinator: RouteCoordinator,
        storageRegistry: StorageRegistry,
        memberContextStore: MemberContextStore,
        chatStateStore: ChatStateStore,
        chatListViewModel: ChatListViewModel,
        chatSyncSupervisor: ChatSyncSupervisor,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        knowledgeSyncSupervisor: KnowledgeSyncSupervisor,
        aiConfigCenter: AIConfigCenter,
        logger: Logger,
        clearSessionScopedViewModels: @escaping () -> Void,
        clearExternalMedicalImport: @escaping () -> Void,
        chatSyncSupervisorForResume: ChatSyncSupervisor? = nil
    ) {
        self.routeCoordinator = routeCoordinator
        self.storageRegistry = storageRegistry
        self.memberContextStore = memberContextStore
        self.chatStateStore = chatStateStore
        self.chatListViewModel = chatListViewModel
        self.chatSyncSupervisor = chatSyncSupervisor
        self.chatSyncSupervisorForResume = chatSyncSupervisorForResume ?? chatSyncSupervisor
        self.knowledgeViewModel = knowledgeViewModel
        self.knowledgeSyncSupervisor = knowledgeSyncSupervisor
        self.aiConfigCenter = aiConfigCenter
        self.logger = logger
        self.clearSessionScopedViewModels = clearSessionScopedViewModels
        self.clearExternalMedicalImport = clearExternalMedicalImport
    }

    /// 同设备账号切换登录前：暂停旧账号实时同步，避免 B1 登录过程中 A1 仍发账号级请求。
    func beginAccountSwitch(suspendedAccountID: Int64?) async {
        guard isAccountSwitchInProgress == false else { return }
        isAccountSwitchInProgress = true
        suspendedAccountIDForSwitch = suspendedAccountID
        logger.info(
            "账号运行时：账号切换登录开始，暂停实时同步 accountID=\(suspendedAccountID.map(String.init) ?? "-")",
            module: .auth
        )
        await chatSyncSupervisor.stopRealtimeSync()
    }

    /// 登录流程结束：commit=true 表示已切到新账号；同账号升级时恢复实时同步。
    func endAccountSwitch(commit: Bool, currentSignedInAccountID: Int64?) async {
        defer {
            isAccountSwitchInProgress = false
            suspendedAccountIDForSwitch = nil
        }
        let suspended = suspendedAccountIDForSwitch
        let current = currentSignedInAccountID

        if commit {
            // 同账号凭证升级：activateUser 会跳过 reset，需在此恢复同步。
            if let suspended, let current, suspended == current {
                logger.info(
                    "账号运行时：同账号升级完成，恢复实时同步 accountID=\(suspended)",
                    module: .auth
                )
                await chatSyncSupervisorForResume?.startRealtimeSync()
            }
            return
        }

        guard let suspended, let current, suspended == current else { return }
        logger.info(
            "账号运行时：账号切换登录失败，恢复实时同步 accountID=\(suspended)",
            module: .auth
        )
        await chatSyncSupervisorForResume?.startRealtimeSync()
    }

    func activateUser(accountID: Int64) async {
        if mode == .account(accountID) {
            logger.debug("账号运行时：账号未变化，跳过重复初始化 accountID=\(accountID)", module: .auth)
            return
        }

        let previousAccountID: Int64? = {
            if case .account(let id) = mode { return id }
            return nil
        }()

        logger.info("账号运行时：开始切换到账号 accountID=\(accountID)", module: .auth)
        await chatSyncSupervisor.stopRealtimeSync()
        // 知识同步：先取消旧账号的同步任务/迟到回调，再切换 Core Data account scope，
        // 避免旧 generation 的网络结果写入新账号存储（工单 5.1.4、6.5.8）。
        await knowledgeSyncSupervisor.cancelForAccountSwitch()
        await storageRegistry.prepareForAccountSwitch(to: accountID)
        await aiConfigCenter.resetRuntimeCaches()
        chatStateStore.resetForSessionSwitch()
        chatListViewModel.resetForSessionSwitch()
        knowledgeViewModel.resetForSessionSwitch()
        memberContextStore.activateAccountAndReset(accountID)
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "accountSwitch(\(accountID))")
        clearSessionScopedViewModels()
        if let previousAccountID, previousAccountID != accountID {
            clearExternalMedicalImport()
        }
        mode = .account(accountID)
        await knowledgeSyncSupervisor.startForAccount(accountID: accountID)
        logger.info("账号运行时：账号切换完成 accountID=\(accountID)", module: .auth)
    }

    func activateGuest() async {
        if mode == .guest {
            logger.debug("账号运行时：已处于未登录运行时，跳过重复清理", module: .auth)
            return
        }

        logger.info("账号运行时：切换到访客/未登录运行时", module: .auth)
        await chatSyncSupervisor.stopRealtimeSync()
        await knowledgeSyncSupervisor.cancelForAccountSwitch()
        await storageRegistry.prepareForSignOut()
        await aiConfigCenter.resetRuntimeCaches()
        chatStateStore.resetForSessionSwitch()
        chatListViewModel.resetForSessionSwitch()
        knowledgeViewModel.resetForSessionSwitch()
        memberContextStore.resetInMemoryContext()
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "signOut")
        clearSessionScopedViewModels()
        clearExternalMedicalImport()
        mode = .guest
    }

    func clearSessionPersistenceAndActivateGuest() async {
        logger.warning("账号运行时：清理会话持久化并回到未登录运行时", module: .auth)
        memberContextStore.clearSessionPersistenceAndReset()
        await activateGuest()
    }
}

extension AccountSessionRuntime: LoginAccountSwitchHandling {
    func beginLoginAccountSwitch(suspendedAccountID: Int64?) async {
        await beginAccountSwitch(suspendedAccountID: suspendedAccountID)
    }

    func endLoginAccountSwitch(commit: Bool, currentSignedInAccountID: Int64?) async {
        await endAccountSwitch(commit: commit, currentSignedInAccountID: currentSignedInAccountID)
    }
}
