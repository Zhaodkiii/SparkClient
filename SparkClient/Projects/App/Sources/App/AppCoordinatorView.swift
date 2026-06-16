import SwiftUI

struct AppCoordinatorView: View {
    private let facades: AppFeatureFacades
    @StateObject private var networkMonitor = NetworkPathMonitor()
    @StateObject private var lifecycle: AppLifecycleCoordinator
    @StateObject private var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject private var onboardingStore: OnboardingStore

    init(dependencies: AppCoordinatorDependencies) {
        self.facades = dependencies.facades
        self.onboardingStore = dependencies.facades.onboarding.store
        _lifecycle = StateObject(wrappedValue: dependencies.lifecycle)
        _versionUpdateCoordinator = StateObject(wrappedValue: dependencies.versionUpdateCoordinator)
    }

    var body: some View {
        ZStack {
            sessionContent
            if networkMonitor.hasEvaluatedPath == false {
                AppLaunchScreenView()
            } else if networkMonitor.isSatisfied == false {
                NetworkGateView(monitor: networkMonitor)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: lifecycle.sessionState)
        .animation(.easeInOut, value: networkMonitor.hasEvaluatedPath)
        .animation(.easeInOut, value: networkMonitor.isSatisfied)
        .modifier(VersionUpdateOverlay(coordinator: versionUpdateCoordinator))
        .onAppear {
            networkMonitor.start()
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch lifecycle.sessionState {
        case .loading:
            AppLaunchScreenView()
                .task(id: networkMonitor.hasEvaluatedPath ? networkMonitor.isSatisfied : false) {
                    await lifecycle.bootstrapLaunchAfterNetworkEvaluation(
                        hasEvaluatedPath: networkMonitor.hasEvaluatedPath,
                        isNetworkSatisfied: networkMonitor.isSatisfied
                    )
                }

        case .signedOut:
            SignedOutAuthCoordinatorView(facades: facades, lifecycle: lifecycle)

        case .signedIn(let session):
            if lifecycle.preparedAccountID == session.accountID {
                let mainTab = facades.mainTab.makeDependencies(session.accountID)
                if onboardingStore.activeAccountID == session.accountID, onboardingStore.needsOnboarding {
                    OnboardingFlowView(
                        viewModel: facades.onboarding.makeFlowViewModel(),
                        memberContextStore: mainTab.memberContextStore,
                        aiSettingsViewModel: mainTab.aiSettingsViewModel
                    )
                    .id("onboarding-\(session.accountID)")
                    .onAppear {
                        mainTab.launchIntentCoordinator.updateReadiness {
                            $0.isSignedIn = true
                            $0.accountID = session.accountID
                            $0.isAccountPrepared = true
                            $0.isOnboardingBlocking = true
                        }
                    }
                } else {
                    MainTabCoordinatorView(
                        session: session,
                        routeStore: mainTab.routeStore,
                        homeDependencies: mainTab.homeDependencies,
                        knowledgeDependencies: mainTab.knowledgeDependencies,
                        taskManager: mainTab.taskManager,
                        homeViewModel: mainTab.homeViewModel,
                        medicalDocumentUploadViewModel: mainTab.medicalDocumentUploadViewModel,
                        knowledgeViewModel: mainTab.knowledgeViewModel,
                        chatStateStore: mainTab.chatStateStore,
                        chatListViewModel: mainTab.chatListViewModel,
                        chatDetailViewModel: mainTab.chatDetailViewModel,
                        settingsViewModel: mainTab.settingsViewModel,
                        accountManagementViewModel: mainTab.accountManagementViewModel,
                        aiSettingsViewModel: mainTab.aiSettingsViewModel,
                        versionUpdateCoordinator: mainTab.versionUpdateCoordinator,
                        pushAdapter: mainTab.pushAdapter,
                        externalMedicalDocumentImportCoordinator: mainTab.externalMedicalDocumentImportCoordinator,
                        launchIntentCoordinator: mainTab.launchIntentCoordinator
                    )
                    .environmentObject(mainTab.memberContextStore)
                    .id(session.accountID)
                    .onAppear {
                        mainTab.launchIntentCoordinator.updateReadiness {
                            $0.isSignedIn = true
                            $0.accountID = session.accountID
                            $0.isAccountPrepared = true
                            $0.isOnboardingBlocking = false
                        }
                    }
                    .task(id: session.accountID) {
                        // 通知权限仅在用户已进入已登录态后询问（含会话恢复），避免登录页弹系统对话框。
//                        lifecycle.requestNotificationAuthorizationIfNeeded()
                        // 设备登记由 AppLifecycleCoordinator / DeviceRegistrationCoordinator 在启动与会话恢复时统一触发。
                        await versionUpdateCoordinator.checkOnLaunchIfNeeded(force: true)
                    }
                }
            } else {
                // 账号准备由 AppLifecycleCoordinator 统一调度（冷启动 / 登录），避免 SwiftUI .task 取消导致登记中断。
                AppLaunchScreenView()
            }
        }
    }
}

/// 登录页容器：缓存 LoginViewModel 生命周期，避免在 AppCoordinatorView.body 中重复创建。
private struct SignedOutAuthCoordinatorView: View {
    let facades: AppFeatureFacades
    let lifecycle: AppLifecycleCoordinator

    @StateObject private var viewModel: LoginViewModel

    init(facades: AppFeatureFacades, lifecycle: AppLifecycleCoordinator) {
        self.facades = facades
        self.lifecycle = lifecycle
        _viewModel = StateObject(wrappedValue: facades.auth.makeLoginViewModel())
    }
    
    var body: some View {
        CompatibleNavigationContainer {
            LoginView(viewModel: viewModel)
        }
        .task {
            await lifecycle.handleSignedOutTask()
        }
        //        AuthCoordinatorView(viewModel: viewModel)
        //            .task {
        //                await lifecycle.handleSignedOutTask()
        //            }
    }
}
