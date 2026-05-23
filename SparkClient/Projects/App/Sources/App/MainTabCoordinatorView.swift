import SwiftUI

/// 主 Tab：`Knowledge` 为本地 Markdown 知识库入口，与 Chat 中 `search_knowledge_bag` 共用数据。
struct MainTabCoordinatorView: View {
    let session: UserSession
    @ObservedObject var routeStore: AppRouteStore
    let homeDependencies: HomeFeatureDependencies
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var chatStateStore: ChatStateStore
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var chatDetailViewModel: ChatDetailViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            CompatibleRouteNavigationContainer(path: routePath(.home)) {
                HomeView(
                    dependencies: homeDependencies,
                    viewModel: homeViewModel,
                    medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                    session: session
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.home"), systemImage: "house.fill")
            }
            .tag(AppRouteStore.RootTab.home)

            CompatibleRouteNavigationContainer(path: routePath(.knowledge)) {
                KnowledgeLibraryView(dependencies: knowledgeDependencies, viewModel: knowledgeViewModel)
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label("Knowledge", systemImage: "books.vertical.fill")
            }
            .tag(AppRouteStore.RootTab.knowledge)

            CompatibleRouteNavigationContainer(path: routePath(.chat)) {
                ChatConversationListPage(
                    stateStore: chatStateStore,
                    listViewModel: chatListViewModel,
                    detailViewModel: chatDetailViewModel,
                    taskManager: taskManager,
                    homeViewModel: homeViewModel
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppRouteStore.RootTab.chat)

            CompatibleRouteNavigationContainer(path: routePath(.settings)) {
                SettingsView(
                    viewModel: settingsViewModel,
                    accountManagementViewModel: accountManagementViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    versionUpdateCoordinator: versionUpdateCoordinator,
                    session: session
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.settings"), systemImage: "gearshape.fill")
            }
            .tag(AppRouteStore.RootTab.settings)
        }
    }

    private func routePath(_ tab: AppRouteStore.RootTab) -> Binding<[AppRoute]> {
        Binding(
            get: {
                routeStore.routes(for: tab)
            },
            set: { routes in
                routeStore.replaceStack(routes, for: tab)
            }
        )
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .chatThread(let threadID):
            ChatView(
                threadID: threadID,
                stateStore: chatStateStore,
                listViewModel: chatListViewModel,
                detailViewModel: chatDetailViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel
            )
            .hidesMainTabBarWhenPushed()
            .task(id: threadID) {
                await chatListViewModel.selectAndPrepare(threadID: threadID)
                await chatDetailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
            }
        case .aiSettings:
            AISettingsView(viewModel: aiSettingsViewModel)
                .hidesMainTabBarWhenPushed()
        case .home, .knowledge, .chatList, .settings, .memberInvite:
            EmptyView()
        }
    }
}
