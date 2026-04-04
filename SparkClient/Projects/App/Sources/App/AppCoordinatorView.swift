import SwiftUI

struct AppCoordinatorView: View {
    let container: AppContainer
    @StateObject private var sessionStore: AppSessionStore

    init(container: AppContainer) {
        self.container = container
        _sessionStore = StateObject(wrappedValue: container.sessionStore)
    }

    var body: some View {
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
                        container.patientContextStore.update(members: [], selectedMemberID: nil)
                    }

            case .signedIn(let session):
                MainTabCoordinatorView(
                    session: session,
                    routeStore: container.routeStore,
                    homeViewModel: container.makeHomeViewModel(),
                    medicalUploadFlowViewModel: container.makeMedicalUploadFlowViewModel(),
                    healthViewModel: container.makeHealthTimelineViewModel(),
                    chatStateStore: container.makeChatStateStore(),
                    chatListViewModel: container.makeChatListViewModel(),
                    chatDetailViewModel: container.makeChatDetailViewModel(),
                    settingsViewModel: container.makeSettingsViewModel(),
                    aiSettingsViewModel: container.makeAISettingsViewModel()
                )
                .task(id: session.profileID) {
                    await container.appBootstrapper.bootstrapIfNeeded(for: session)
                }
            }
        }
        .animation(.easeInOut, value: sessionStore.state)
    }
}
