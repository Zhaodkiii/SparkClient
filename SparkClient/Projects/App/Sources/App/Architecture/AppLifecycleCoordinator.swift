import Combine
import Foundation

/// 应用生命周期协调器：把根视图中的副作用集中到一处，根视图只负责根据状态渲染。
@MainActor
final class AppLifecycleCoordinator: ObservableObject {
    let sessionStore: AppSessionStore

    /// 根视图直接观察的会话状态。
    ///
    /// 不让 SwiftUI 直接读取嵌套的 `sessionStore.state`，否则 `AppSessionStore` 变化不会触发
    /// `AppLifecycleCoordinator.objectWillChange`，登录成功后根视图可能停留在 signedOut。
    @Published private(set) var sessionState: AppSessionStore.State = .loading
    @Published private(set) var preparedAccountID: Int64?

    private let container: AppContainer
    private let logger: Logger
    private var cancellables: Set<AnyCancellable> = []
    private var isHandlingServerAuthInvalidation = false
    private var didHandleSignedOutState = false
    private var isColdLaunchBootstrapInProgress = false
    private var lastObservedSessionState: AppSessionStore.State = .loading
    private let signedInPreparationRegistry = SignedInSessionPreparationRegistry()

    init(container: AppContainer) {
        self.container = container
        self.logger = container.logger
        self.sessionStore = container.sessionStore
        self.sessionState = container.sessionStore.state
        self.lastObservedSessionState = container.sessionStore.state
        self.preparedAccountID = signedInPreparationRegistry.preparedAccountID

        container.sessionStore.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                let previous = self.lastObservedSessionState
                self.lastObservedSessionState = state
                self.sessionState = state
                self.logger.debug("根生命周期：会话状态已同步到根视图 state=\(state.logValue)", module: .auth)
                Task { await self.handleSessionStateTransition(from: previous, to: state) }
            }
            .store(in: &cancellables)
        logger.info("AppLifecycleCoordinator 已初始化", module: .general)
    }

    func bootstrapLaunchAfterNetworkEvaluation(hasEvaluatedPath: Bool, isNetworkSatisfied: Bool) async {
        guard hasEvaluatedPath else { return }
        guard isNetworkSatisfied else {
            logger.info("启动流程：网络路径已评估但当前不可用，等待网络恢复后再执行引导与会话恢复", module: .general)
            return
        }
        logger.info("启动流程：网络路径已评估且可用，开始会话恢复与应用级引导", module: .general)

        isColdLaunchBootstrapInProgress = true
        defer { isColdLaunchBootstrapInProgress = false }

        await sessionStore.restoreIfNeeded()
        await container.appBootstrapper.bootstrapAppLaunchIfNeeded()

        switch sessionStore.state {
        case .signedIn(let session):
            await enqueueSignedInPreparation(
                session: session,
                deviceRegistrationReason: .signedInColdLaunch
            )
        case .signedOut:
            await registerDeviceForSignedOutLaunchIfNeeded()
        case .loading:
            break
        }
    }

    func handleSignedOutTask() async {
        guard didHandleSignedOutState == false else {
            logger.debug("会话流程：已处理未登录态，跳过重复清理", module: .auth)
            return
        }

        logger.info("会话流程：进入未登录态，清理账号运行时", module: .auth)
        didHandleSignedOutState = true
        resetSignedInLaunchPreparationState()
        container.onboardingStore.deactivate()
        let preserveDeviceRegistration = container.deviceRegistrationCoordinator.hasPendingAnonymousRegistration
        await container.appBootstrapper.reset()
        if preserveDeviceRegistration == false {
            container.deviceRegistrationCoordinator.reset()
        }
        await container.accountSessionRuntime.activateGuest()
    }

    func syncForegroundWorkIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        guard isHandlingServerAuthInvalidation == false else { return }
        guard container.accountSessionRuntime.isAccountSwitchInProgress == false else { return }
        logger.debug("前台流程：应用回到前台，先检查设备登记再同步业务", module: .general)
        await container.deviceRegistrationCoordinator.handleForegroundResume()
        guard case .signedIn = sessionStore.state, isHandlingServerAuthInvalidation == false else { return }
        await container.knowledgeSyncSupervisor.scheduleForegroundSyncIfNeeded()
        await container.taskRuntime.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)
        await container.versionUpdateCoordinator.checkOnLaunchIfNeeded()
        if case .signedIn(let session) = sessionStore.state {
            container.medicationReminderSyncCoordinator.rebuildIfStale(
                accountID: session.accountID,
                members: container.memberContextStore.context.members,
                reason: "foreground_resume"
            )
        }
    }

    func handleServerAuthInvalidationIfNeeded(invalidationMessage: String = "") async {
        guard isHandlingServerAuthInvalidation == false else { return }

        switch sessionStore.state {
        case .signedOut:
            return
        case .loading, .signedIn:
            break
        }

        logger.warning("认证流程：收到服务端鉴权失效通知，准备强制回到登录态", module: .auth)
        isHandlingServerAuthInvalidation = true
        container.deviceRegistrationCoordinator.suspendPendingSubmissions()
        resetSignedInLaunchPreparationState()
        sessionStore.setSignedOut()
        defer { isHandlingServerAuthInvalidation = false }
        await container.forceSignOutAfterServerAuthInvalidation(invalidationMessage: invalidationMessage)
        await container.appBootstrapper.reset()
        container.deviceRegistrationCoordinator.reset()
    }

    // MARK: - 已登录准备（单一入口，不经过 SwiftUI .task）

    private func handleSessionStateTransition(
        from previous: AppSessionStore.State,
        to current: AppSessionStore.State
    ) async {
        guard case .signedIn(let session) = current else { return }
        guard isColdLaunchBootstrapInProgress == false else { return }

        switch previous {
        case .signedOut:
            await enqueueSignedInPreparation(
                session: session,
                deviceRegistrationReason: .signedInBootstrap
            )
        case .signedIn(let previousSession) where previousSession.accountID != session.accountID:
            await enqueueSignedInPreparation(
                session: session,
                deviceRegistrationReason: .signedInBootstrap
            )
        case .loading:
            // 冷启动路径由 `bootstrapLaunchAfterNetworkEvaluation` 负责。
            break
        default:
            break
        }
    }

    private func enqueueSignedInPreparation(
        session: UserSession,
        deviceRegistrationReason: DeviceRegistrationReason
    ) async {
        await signedInPreparationRegistry.runPreparationIfNeeded(accountID: session.accountID) {
            await self.runSignedInPreparation(
                session: session,
                deviceRegistrationReason: deviceRegistrationReason
            )
        }
        preparedAccountID = signedInPreparationRegistry.preparedAccountID
    }

    private func runSignedInPreparation(
        session: UserSession,
        deviceRegistrationReason: DeviceRegistrationReason
    ) async {
        logger.info("会话流程：准备账号运行时 accountID=\(session.accountID)", module: .auth)
        didHandleSignedOutState = false

        logger.debug("会话流程：准备步骤 activateUser 开始 accountID=\(session.accountID)", module: .auth)
        await container.accountSessionRuntime.activateUser(accountID: session.accountID)
        // 知识同步：非阻断调度，立即返回；不等待网络完成，不影响后续启动步骤（工单 6.5）。
        await container.knowledgeSyncSupervisor.scheduleStartupSync(accountID: session.accountID)
        logger.debug("会话流程：准备步骤 onboarding activate 开始 accountID=\(session.accountID)", module: .auth)
        await container.onboardingStore.activate(session: session)

        logger.debug(
            "会话流程：准备步骤 signedInDeviceRegistration 开始 accountID=\(session.accountID) reason=\(deviceRegistrationReason.rawValue)",
            module: .auth
        )
        let registrationOutcome = await container.deviceRegistrationCoordinator.requestRegisterWithLimitedRetry(
            reason: deviceRegistrationReason,
            accountID: Int(session.accountID)
        )
        switch registrationOutcome {
        case .authSessionInvalidated:
            logger.warning(
                "会话流程：设备登记鉴权失效，中止账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        case .failedRetryable:
            logger.warning(
                "会话流程：设备登记失败且重试已用尽，中止账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        case .submitted, .skippedSameLaunchSubmission:
            break
        }

        guard registrationOutcome.allowsAccountBootstrap else {
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }

        guard case .signedIn = sessionStore.state, isHandlingServerAuthInvalidation == false else {
            logger.warning(
                "会话流程：设备登记后鉴权失效，跳过后续账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }

        logger.debug("会话流程：准备步骤 bootstrapIfNeeded 开始 accountID=\(session.accountID)", module: .auth)
        await container.appBootstrapper.bootstrapIfNeeded(for: session)
        guard case .signedIn = sessionStore.state, isHandlingServerAuthInvalidation == false else {
            logger.warning(
                "会话流程：账号引导后鉴权失效，跳过后续 home/task 同步 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }
        logger.debug("会话流程：准备步骤 home loadInitialIfNeeded 开始 accountID=\(session.accountID)", module: .auth)
        await container.makeHomeViewModel().loadInitialIfNeeded(syncRemote: true)
        logger.debug("会话流程：准备步骤 task syncIncremental 开始 accountID=\(session.accountID)", module: .auth)
        await container.taskRuntime.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)

        signedInPreparationRegistry.markPrepared(accountID: session.accountID)
        preparedAccountID = session.accountID
        logger.info("会话流程：账号运行时准备完成 accountID=\(session.accountID)", module: .auth)
        container.medicationReminderSyncCoordinator.activate(accountID: session.accountID)
        container.medicationReminderSyncCoordinator.requestRebuild(
            accountID: session.accountID,
            members: container.memberContextStore.context.members,
            reason: "signed_in_bootstrap",
            immediate: true
        )
    }

    // MARK: - 设备登记（单一入口）

    private func registerDeviceForSignedOutLaunchIfNeeded() async {
        logger.debug("设备登记：未登录冷启动，触发匿名登记", module: .network)
        _ = await container.deviceRegistrationCoordinator.requestRegisterWithLimitedRetry(reason: .appLaunch)
    }

    private func resetSignedInLaunchPreparationState() {
        signedInPreparationRegistry.reset()
        preparedAccountID = nil
    }
}

private extension AppSessionStore.State {
    var logValue: String {
        switch self {
        case .loading:
            return "loading"
        case .signedOut:
            return "signedOut"
        case .signedIn(let session):
            return "signedIn(\(session.accountID))"
        }
    }
}
