import SwiftUI
import UIKit

struct AppCoordinatorView: View {
    let container: AppContainer
    @StateObject private var sessionStore: AppSessionStore
    @StateObject private var networkMonitor = NetworkPathMonitor()
    @State private var isHandlingServerAuthInvalidation = false
    @State private var preparedAccountID: Int64?
    @State private var preparingAccountID: Int64?

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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { @MainActor in
                guard case .signedIn = sessionStore.state else { return }
                await TaskManager.shared.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)
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
                        if case .signedIn(let session) = sessionStore.state {
                            await prepareSignedInSessionIfNeeded(session)
                        }
                    }

            case .signedOut:
                AuthCoordinatorView(viewModel: container.makeLoginViewModel())
                    .task {
                        preparedAccountID = nil
                        preparingAccountID = nil
                        await container.appBootstrapper.reset()
                        container.activateGuestLocalStore()
                    }

            case .signedIn(let session):
                if preparedAccountID == session.accountID {
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
                    .id(session.accountID)
                    .task(id: session.accountID) {
                        // 通知权限仅在用户已进入已登录态后询问（含会话恢复），避免登录页弹系统对话框。
                        container.pushAdapter.requestAuthorizationIfNeeded()
                    }
                } else {
                    ProgressView(L10n.text("app.loading.preparing"))
                        .task(id: session.accountID) {
                            await prepareSignedInSessionIfNeeded(session)
                        }
                }
            }
        }
    }

    private func prepareSignedInSessionIfNeeded(_ session: UserSession) async {
        guard preparedAccountID != session.accountID else { return }
        guard preparingAccountID != session.accountID else { return }

        preparingAccountID = session.accountID
        defer { preparingAccountID = nil }

        container.activateUserScopedLocalStore(accountID: session.accountID)
        await container.appBootstrapper.bootstrapIfNeeded(for: session)
        await container.makeHomeViewModel().loadInitialIfNeeded(syncRemote: true)
        await TaskManager.shared.syncIncremental(memberID: container.memberContextStore.context.selectedMemberID)
        preparedAccountID = session.accountID
    }

    private func handleServerAuthInvalidationIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        guard isHandlingServerAuthInvalidation == false else { return }

        isHandlingServerAuthInvalidation = true
        defer { isHandlingServerAuthInvalidation = false }
        await container.forceSignOutAfterServerAuthInvalidation()
    }
}
