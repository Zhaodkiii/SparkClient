import SwiftUI

/// 主 Tab：`Knowledge` 为本地 Markdown 知识库入口，与 Chat 中 `search_knowledge_bag` 共用数据。
struct MainTabCoordinatorView: View {
    let session: UserSession
    @ObservedObject var routeStore: AppRouteStore
    let appContainer: AppContainer
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var healthViewModel: HealthTimelineViewModel
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var chatStateStore: ChatStateStore
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var chatDetailViewModel: ChatDetailViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            NavigationView {
                HomeView(
                    viewModel: homeViewModel,
                    medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
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
                KnowledgeLibraryView(appContainer: appContainer, viewModel: knowledgeViewModel)
            }
            .tabItem {
                Label("Knowledge", systemImage: "books.vertical.fill")
            }
            .tag(AppRouteStore.RootTab.knowledge)

            NavigationView {
                ChatConversationListPage(
                    stateStore: chatStateStore,
                    listViewModel: chatListViewModel,
                    detailViewModel: chatDetailViewModel
                )
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
