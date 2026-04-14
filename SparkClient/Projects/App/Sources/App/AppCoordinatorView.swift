import SwiftUI

struct AppCoordinatorView: View {
    let container: AppContainer
    @StateObject private var sessionStore: AppSessionStore
    @StateObject private var networkMonitor = NetworkPathMonitor()
    @State private var isHandlingServerAuthInvalidation = false

    init(container: AppContainer) {
        self.container = container
        _sessionStore = StateObject(wrappedValue: container.sessionStore)
    }

    var body: some View {
        Group {
            if networkMonitor.hasEvaluatedPath == false {
                ProgressView(L10n.text("app.loading.preparing"))
            } else if networkMonitor.isSatisfied == false {
                NetworkGateView(monitor: networkMonitor)
            } else {
                sessionContent
            }
        }
        .animation(.easeInOut, value: sessionStore.state)
        .onAppear {
            networkMonitor.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: AuthSessionInvalidation.notificationName)) { _ in
            Task { @MainActor in
                await handleServerAuthInvalidationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        Group {
            switch sessionStore.state {
            case .loading:
                ProgressView(L10n.text("app.loading.preparing"))
                    .task {
                        await container.appBootstrapper.bootstrapAppLaunchIfNeeded()
                        await sessionStore.restoreIfNeeded()
                    }

            case .signedOut:
                AuthCoordinatorView(viewModel: container.makeLoginViewModel())
                    .task {
                        await container.appBootstrapper.reset()
                        container.memberContextStore.resetInMemoryContext()
                        container.resetSessionScopedViewModels()
                    }

            case .signedIn(let session):
                MainTabCoordinatorView(
                    session: session,
                    routeStore: container.routeStore,
                    appContainer: container,
                    homeViewModel: container.makeHomeViewModel(),
                    medicalDocumentUploadViewModel: container.makeMedicalDocumentUploadViewModel(),
                    knowledgeViewModel: container.makeKnowledgeLibraryViewModel(),
                    chatStateStore: container.makeChatStateStore(),
                    chatListViewModel: container.makeChatListViewModel(),
                    chatDetailViewModel: container.makeChatDetailViewModel(),
                    settingsViewModel: container.makeSettingsViewModel(),
                    aiSettingsViewModel: container.makeAISettingsViewModel()
                )
                .environmentObject(container.memberContextStore)
                .task(id: session.profileID) {
                    container.memberContextStore.setActiveProfile(session.profileID)
                    await container.appBootstrapper.bootstrapIfNeeded(for: session)
                    // 通知权限仅在用户已进入已登录态后询问（含会话恢复），避免登录页弹系统对话框。
                    container.pushAdapter.requestAuthorizationIfNeeded()
                }
            }
        }
    }

    private func handleServerAuthInvalidationIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        guard isHandlingServerAuthInvalidation == false else { return }

        isHandlingServerAuthInvalidation = true
        defer { isHandlingServerAuthInvalidation = false }
        await container.forceSignOutAfterServerAuthInvalidation()
    }
}
