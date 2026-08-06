import SwiftUI

/// 主 Tab：`Knowledge` 为本地 Markdown 知识库入口，与 Chat 中 `search_knowledge_bag` 共用数据。
struct MainTabCoordinatorView: View {
    let session: UserSession
    @ObservedObject var routeStore: AppRouteStore
    let homeDependencies: HomeFeatureDependencies
    let knowledgeDependencies: KnowledgeFeatureDependencies
    let popularScienceDependencies: PopularScienceFeatureDependencies
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var popularScienceViewModel: PopularScienceHomeViewModel
    @ObservedObject var chatStateStore: ChatStateStore
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var chatDetailViewModel: ChatDetailViewModel
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject var upgradeLoginViewModel: LoginViewModel
    let pushAdapter: PushAdapter
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator

    @State private var showsDeviceAccountUpgradeSheet = false

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            CompatibleRouteNavigationContainer(path: routePath(.home)) {
                HomeView(
                    dependencies: homeDependencies,
                    viewModel: homeViewModel,
                    medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                    externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
                    launchIntentCoordinator: launchIntentCoordinator,
                    session: session
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.home"), systemImage: "house.fill")
            }
            .tag(AppRouteStore.RootTab.home)

            CompatibleRouteNavigationContainer(path: routePath(.chat)) {
                ChatConversationListPage(
                    stateStore: chatStateStore,
                    listViewModel: chatListViewModel,
                    detailViewModel: chatDetailViewModel,
                    taskManager: taskManager,
                    homeViewModel: homeViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    pushAdapter: pushAdapter
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppRouteStore.RootTab.chat)

            CompatibleRouteNavigationContainer(path: routePath(.deepTutor)) {
                DeepTutorConversationListPage(viewModel: deepTutorChatViewModel)
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.deep_tutor"), systemImage: "graduationcap.fill")
            }
            .tag(AppRouteStore.RootTab.deepTutor)

            CompatibleRouteNavigationContainer(path: routePath(.popularScience)) {
                PopularScienceHomeView(viewModel: popularScienceViewModel)
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.popular_science"), systemImage: "book.pages.fill")
            }
            .tag(AppRouteStore.RootTab.popularScience)

            CompatibleRouteNavigationContainer(path: routePath(.settings)) {
                SettingsView(
                    viewModel: settingsViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    versionUpdateCoordinator: versionUpdateCoordinator,
                    session: session,
                    onAccountEntryTap: handleAccountEntryTap
                )
            } destination: { route in
                routeDestination(route)
            }
            .tabItem {
                Label(L10n.text("tab.settings"), systemImage: "gearshape.fill")
            }
            .tag(AppRouteStore.RootTab.settings)
        }
        .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
//            NavigationView {
//                LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
//                    .toolbar {
//                        ToolbarItem(placement: .cancellationAction) {
//                            Button(L10n.text("common.cancel")) {
//                                guard upgradeLoginViewModel.isLoading == false else { return }
//                                showsDeviceAccountUpgradeSheet = false
//                            }
//                            .disabled(upgradeLoginViewModel.isLoading)
//                        }
//                    }
//            }
//            .interactiveDismissDisabled(upgradeLoginViewModel.isLoading)
            
            LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)

        }
        .onChange(of: session.isDeviceAccount) { isDeviceAccount in
            if isDeviceAccount == false {
                showsDeviceAccountUpgradeSheet = false
            }
        }
        .onChange(of: session.accountID) { _ in
            if session.isDeviceAccount == false {
                showsDeviceAccountUpgradeSheet = false
            }
        }
        .onAppear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
        }
        .onDisappear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = false }
        }
    }

    private func handleAccountEntryTap() {
        if session.isDeviceAccount {
            showsDeviceAccountUpgradeSheet = true
        } else {
            routeStore.route(to: .accountManagement)
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
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel
            )
            .task(id: threadID) {
                await chatListViewModel.selectAndPrepare(threadID: threadID)
                await chatDetailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
            }
        case .deepTutorThread(let conversationID):
            DeepTutorChatPage(conversationID: conversationID, viewModel: deepTutorChatViewModel)
        case .aiSettings:
            AISettingsView(viewModel: aiSettingsViewModel)
        case .accountManagement:
            AccountManagementView(viewModel: accountManagementViewModel, session: session)
        case .homeMedicalList(let listRoute, let medicationFocus):
            HomeMedicalRouteSupport.medicalListView(
                route: listRoute,
                medicationFocus: medicationFocus,
                homeViewModel: homeViewModel,
                dependencies: homeDependencies,
                session: session
            )
        case .homeFamilyMedicineCabinet(let memberID):
            HomeMedicalRouteSupport.familyMedicineCabinetView(
                memberID: memberID,
                homeViewModel: homeViewModel,
                dependencies: homeDependencies
            )
        case .popularScienceArticle(let articleID):
            PopularScienceArticleDetailView(
                viewModel: popularScienceDependencies.makeDetailViewModel(articleID)
            )
        case .home, .knowledge, .chatList, .popularScience, .settings, .deepTutorList:
            EmptyView()
        }
    }
}
