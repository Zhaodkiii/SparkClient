import Combine
import Foundation

/// 应用生命周期协调器：把根视图中的副作用集中到一处，根视图只负责根据状态渲染。
@MainActor
final class AppLifecycleCoordinator: ObservableObject {
    let sessionStore: AppSessionStore

    @Published private(set) var preparedAccountID: Int64?

    private let container: AppContainer
    private let logger: Logger
    private var isHandlingServerAuthInvalidation = false
    private var preparingAccountID: Int64?
    private var didHandleSignedOutState = false

    init(container: AppContainer) {
        self.container = container
        self.logger = container.logger
        self.sessionStore = container.sessionStore
        logger.info("AppLifecycleCoordinator 已初始化", module: .general)
    }

    func bootstrapLaunchAfterNetworkEvaluation(_ hasEvaluatedPath: Bool) async {
        guard hasEvaluatedPath else { return }
        logger.info("启动流程：网络路径已评估，开始应用级引导与会话恢复", module: .general)
        await container.appBootstrapper.bootstrapAppLaunchIfNeeded()
        await sessionStore.restoreIfNeeded()
        if case .signedIn(let session) = sessionStore.state {
            await prepareSignedInSessionIfNeeded(session)
        }
    }

    func handleSignedOutTask() async {
        guard didHandleSignedOutState == false else {
            logger.debug("会话流程：已处理未登录态，跳过重复清理", module: .auth)
            return
        }

        logger.info("会话流程：进入未登录态，清理账号运行时", module: .auth)
        didHandleSignedOutState = true
        preparedAccountID = nil
        preparingAccountID = nil
        await container.appBootstrapper.reset()
        await container.accountSessionRuntime.activateGuest()
    }

    func prepareSignedInSessionIfNeeded(_ session: UserSession) async {
        guard preparedAccountID != session.accountID else { return }
        guard preparingAccountID != session.accountID else { return }

        logger.info("会话流程：准备账号运行时 accountID=\(session.accountID)", module: .auth)
        didHandleSignedOutState = false
        preparingAccountID = session.accountID
        defer { preparingAccountID = nil }

        await container.accountSessionRuntime.activateUser(accountID: session.accountID)
        await container.appBootstrapper.bootstrapIfNeeded(for: session)
        await container.makeHomeViewModel().loadInitialIfNeeded(syncRemote: true)
        await container.taskRuntime.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)
        preparedAccountID = session.accountID
        logger.info("会话流程：账号运行时准备完成 accountID=\(session.accountID)", module: .auth)
    }

    func requestNotificationAuthorizationIfNeeded() {
        logger.debug("通知流程：请求通知权限（如尚未请求）", module: .push)
        container.pushAdapter.requestAuthorizationIfNeeded()
    }

    func syncForegroundWorkIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        logger.debug("前台流程：应用回到前台，触发任务增量同步", module: .general)
        await container.taskRuntime.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)
    }

    func handleServerAuthInvalidationIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        guard isHandlingServerAuthInvalidation == false else { return }

        logger.warning("认证流程：收到服务端鉴权失效通知，准备强制回到登录态", module: .auth)
        isHandlingServerAuthInvalidation = true
        defer { isHandlingServerAuthInvalidation = false }
        await container.forceSignOutAfterServerAuthInvalidation()
    }
}
