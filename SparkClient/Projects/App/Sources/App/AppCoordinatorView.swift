import StoreKit
import SwiftUI
import UIKit

enum AppStoreReviewRequester {
    private static let didRequestKey = "app_store_review.did_request"

    @MainActor
    static func requestIfNeeded() {
        guard UserDefaults.standard.bool(forKey: didRequestKey) == false else {
            return
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        // 这是应用级状态，不绑定账户；系统评分请求只发起一次。
        UserDefaults.standard.set(true, forKey: didRequestKey)
        SKStoreReviewController.requestReview(in: scene)
    }
}

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
            if lifecycle.isAutomaticGuestLoginInProgress {
                AppLaunchScreenView()
            } else {
                SignedOutAuthCoordinatorView(facades: facades, lifecycle: lifecycle)
            }
            
        case .signedIn(let session):
            if lifecycle.preparedAccountID == session.accountID {
                let mainTab = facades.mainTab.makeDependencies(session.accountID)
                if onboardingStore.activeAccountID == session.accountID, onboardingStore.needsOnboarding {
                    OnboardingFlowView(
                        viewModel: facades.onboarding.makeFlowViewModel(),
                        memberContextStore: mainTab.memberContextStore,
                        aiSettingsViewModel: mainTab.aiSettingsViewModel,
                        sessionStore: lifecycle.sessionStore,
                        subscriptionSyncCoordinator: lifecycle.subscriptionSyncCoordinator,
                        homeDependencies: mainTab.homeDependencies
                    ) {
                        Task { @MainActor in
                            await mainTab.homeViewModel.forceReload(syncRemote: true)
                        }
                    }
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
                    SignedInMainTabHostView(
                        session: session,
                        mainTab: mainTab,
                        sessionStore: lifecycle.sessionStore
                    )
                    .environmentObject(mainTab.memberContextStore)
                    .environmentObject(lifecycle.subscriptionSyncCoordinator)
                    .id(session.accountID)
                    .onAppear {
                        mainTab.launchIntentCoordinator.updateReadiness {
                            $0.isSignedIn = true
                            $0.accountID = session.accountID
                            $0.isAccountPrepared = true
                            $0.isOnboardingBlocking = false
                        }
                        Task { @MainActor in
                            // 等待首页完成挂载，确保评分请求绑定到前台窗口场景。
                            try? await Task.sleep(for: .milliseconds(500))
                            guard Task.isCancelled == false else { return }
                            AppStoreReviewRequester.requestIfNeeded()
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
    
        LoginView(viewModel: viewModel)
        .task {
            await lifecycle.handleSignedOutTask()
        }
        //        AuthCoordinatorView(viewModel: viewModel)
        //            .task {
        //                await lifecycle.handleSignedOutTask()
        //            }
    }
}
