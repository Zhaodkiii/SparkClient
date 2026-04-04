import SwiftUI

struct MainTabCoordinatorView: View {
    let session: UserSession
    @ObservedObject var routeStore: AppRouteStore
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var medicalUploadFlowViewModel: MedicalUploadFlowViewModel
    @ObservedObject var healthViewModel: HealthTimelineViewModel
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            NavigationView {
                HomeView(
                    viewModel: homeViewModel,
                    medicalUploadFlowViewModel: medicalUploadFlowViewModel,
                    session: session,
                    onOpenHealthTimeline: {
                        routeStore.selectedTab = .health
                    }
                )
            }
            .tabItem {
                Label(L10n.text("tab.home"), systemImage: "house.fill")
            }
            .tag(AppRouteStore.RootTab.home)

            NavigationView {
                HealthTimelineView(viewModel: healthViewModel, session: session)
            }
            .tabItem {
                Label(L10n.text("tab.health"), systemImage: "waveform.path.ecg")
            }
            .tag(AppRouteStore.RootTab.health)

            NavigationView {
                ChatView(viewModel: chatViewModel)
            }
            .tabItem {
                Label(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppRouteStore.RootTab.chat)

            NavigationView {
                SettingsView(
                    viewModel: settingsViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    session: session
                )
            }
            .tabItem {
                Label(L10n.text("tab.settings"), systemImage: "gearshape.fill")
            }
            .tag(AppRouteStore.RootTab.settings)
        }
    }
}
