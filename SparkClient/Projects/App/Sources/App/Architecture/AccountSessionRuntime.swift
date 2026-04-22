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
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger
    private let clearSessionScopedViewModels: () -> Void
    private var mode: Mode?

    init(
        routeCoordinator: RouteCoordinator,
        storageRegistry: StorageRegistry,
        memberContextStore: MemberContextStore,
        chatStateStore: ChatStateStore,
        chatListViewModel: ChatListViewModel,
        chatSyncSupervisor: ChatSyncSupervisor,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        aiConfigCenter: AIConfigCenter,
        logger: Logger,
        clearSessionScopedViewModels: @escaping () -> Void
    ) {
        self.routeCoordinator = routeCoordinator
        self.storageRegistry = storageRegistry
        self.memberContextStore = memberContextStore
        self.chatStateStore = chatStateStore
        self.chatListViewModel = chatListViewModel
        self.chatSyncSupervisor = chatSyncSupervisor
        self.knowledgeViewModel = knowledgeViewModel
        self.aiConfigCenter = aiConfigCenter
        self.logger = logger
        self.clearSessionScopedViewModels = clearSessionScopedViewModels
    }

    func activateUser(accountID: Int64) async {
        if mode == .account(accountID) {
            logger.debug("账号运行时：账号未变化，跳过重复初始化 accountID=\(accountID)", module: .auth)
            return
        }

        logger.info("账号运行时：开始切换到账号 accountID=\(accountID)", module: .auth)
        await chatSyncSupervisor.stopRealtimeSync()
        await storageRegistry.prepareForAccountSwitch(to: accountID)
        await aiConfigCenter.resetRuntimeCaches()
        chatStateStore.resetForSessionSwitch()
        chatListViewModel.resetForSessionSwitch()
        knowledgeViewModel.resetForSessionSwitch()
        memberContextStore.activateAccountAndReset(accountID)
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "accountSwitch(\(accountID))")
        clearSessionScopedViewModels()
        mode = .account(accountID)
        logger.info("账号运行时：账号切换完成 accountID=\(accountID)", module: .auth)
    }

    func activateGuest() async {
        if mode == .guest {
            logger.debug("账号运行时：已处于未登录运行时，跳过重复清理", module: .auth)
            return
        }

        logger.info("账号运行时：切换到访客/未登录运行时", module: .auth)
        await chatSyncSupervisor.stopRealtimeSync()
        await storageRegistry.prepareForSignOut()
        await aiConfigCenter.resetRuntimeCaches()
        chatStateStore.resetForSessionSwitch()
        chatListViewModel.resetForSessionSwitch()
        knowledgeViewModel.resetForSessionSwitch()
        memberContextStore.resetInMemoryContext()
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "signOut")
        clearSessionScopedViewModels()
        mode = .guest
    }

    func clearSessionPersistenceAndActivateGuest() async {
        logger.warning("账号运行时：清理会话持久化并回到未登录运行时", module: .auth)
        memberContextStore.clearSessionPersistenceAndReset()
        await activateGuest()
    }
}
