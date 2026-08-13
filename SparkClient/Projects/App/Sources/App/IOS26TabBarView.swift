import SwiftUI

/// iOS 26 正式主导航：系统 Liquid Glass 浮动 TabBar，底部 Tab 为首页、对话、知识背包、搜索、设置（IOS26-TABBAR-000002）。
@available(iOS 26.0, *)
struct IOS26TabBarView: View {
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
    @ObservedObject var chatAutoSmallTaskIntentStore: ChatAutoSmallTaskIntentStore
    let chatAutoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator
    let autoSmallTaskRegistry: AutoSmallTaskRegistry
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject var upgradeLoginViewModel: LoginViewModel
    let pushAdapter: PushAdapter
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator
    @Binding var activeHomeFullScreenCover: HomeFullScreenCover?

    @State private var showsDeviceAccountUpgradeSheet = false

    private var destinationBuilder: MainTabRouteDestinationBuilder {
        MainTabRouteDestinationBuilder(
            session: session,
            homeDependencies: homeDependencies,
            knowledgeDependencies: knowledgeDependencies,
            popularScienceDependencies: popularScienceDependencies,
            homeViewModel: homeViewModel,
            knowledgeViewModel: knowledgeViewModel,
            taskManager: taskManager,
            chatStateStore: chatStateStore,
            chatListViewModel: chatListViewModel,
            chatDetailViewModel: chatDetailViewModel,
            chatAutoSmallTaskCoordinator: chatAutoSmallTaskCoordinator,
            deepTutorChatViewModel: deepTutorChatViewModel,
            accountManagementViewModel: accountManagementViewModel,
            aiSettingsViewModel: aiSettingsViewModel
        )
    }

    private var homeDashboardActionHandler: IOS26HomeDashboardActionHandler {
        IOS26HomeDashboardActionHandler(
            routeStore: routeStore,
            homeViewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            chatListViewModel: chatListViewModel,
            deepTutorChatViewModel: deepTutorChatViewModel,
            notificationClient: homeDependencies.notificationClient,
            quickStartPreferenceStore: .shared,
            autoSmallTaskRegistry: autoSmallTaskRegistry,
            autoSmallTaskIntentStore: chatAutoSmallTaskIntentStore,
            ownerAccountID: session.accountID
        )
    }

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            Tab(L10n.text("tab.home"), systemImage: "house.fill", value: AppRouteStore.RootTab.home) {
                homeContainer
            }

            Tab(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill", value: AppRouteStore.RootTab.chat,role: .search) {
                chatContainer
            }

            Tab(L10n.text("tab.health"), systemImage: "heart.fill", value: AppRouteStore.RootTab.health) {
                healthContainer
            }

//            Tab(L10n.text("tab.knowledge"), systemImage: "backpack.fill", value: AppRouteStore.RootTab.knowledge) {
//                knowledgeContainer
//            }

            
/// iOS 26 正式主导航：系统 Liquid Glass 浮动 TabBar，底部 Tab 为首页、对话、DeepTutor、搜索、设置（IOS26-TABBAR-000002）。
//            Tab(L10n.text("tab.deep_tutor"), systemImage: "graduationcap.fill", value: AppRouteStore.RootTab.deepTutor) {
//                deepTutorContainer
//            }
            
//            Tab(L10n.text("tab.search"), systemImage: "magnifyingglass", value: AppRouteStore.RootTab.search, role: .search) {
//                IOS26SearchTabView()
//            }

//            Tab(L10n.text("tab.settings"), systemImage: "gearshape.fill", value: AppRouteStore.RootTab.settings) {
//                settingsContainer
//            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
            LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
        }
        .onChange(of: session.isDeviceAccount) { _, isDeviceAccount in
            if isDeviceAccount == false {
                showsDeviceAccountUpgradeSheet = false
            }
        }
        .onChange(of: session.accountID) { _, _ in
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

    private var homeContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.home)) {
            IOS26HomeView(
                dependencies: homeDependencies,
                viewModel: homeViewModel,
                taskManager: taskManager,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: launchIntentCoordinator,
                session: session,
                actionHandler: homeDashboardActionHandler,
                chatListViewModel: chatListViewModel,
                deepTutorChatViewModel: deepTutorChatViewModel,
                settingsViewModel: settingsViewModel,
                accountManagementViewModel: accountManagementViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                versionUpdateCoordinator: versionUpdateCoordinator,
                showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet,
                activeFullScreenCover: $activeHomeFullScreenCover
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var chatContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.chat)) {
            ChatConversationListPage(
                stateStore: chatStateStore,
                listViewModel: chatListViewModel,
                detailViewModel: chatDetailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                pushAdapter: pushAdapter
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var healthContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.health)) {
            HealthHomeView(
                dependencies: homeDependencies,
                viewModel: homeViewModel,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: launchIntentCoordinator,
                session: session,
                activeFullScreenCover: $activeHomeFullScreenCover
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var deepTutorContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.deepTutor)) {
            DeepTutorConversationListPage(
                viewModel: deepTutorChatViewModel,
                aiSettingsViewModel: aiSettingsViewModel
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var knowledgeContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.knowledge)) {
            KnowledgeLibraryView(
                dependencies: knowledgeDependencies,
                viewModel: knowledgeViewModel
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var settingsContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.settings)) {
            SettingsView(
                viewModel: settingsViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                accountManagementViewModel: accountManagementViewModel,
                versionUpdateCoordinator: versionUpdateCoordinator,
                session: session,
                showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet
            )
        } destination: { route in
            destinationBuilder.destination(route)
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
}

@available(iOS 26.0, *)
private struct IOS26SearchTabView: View {
    @State private var query = ""

    private let recentSearches = [
        L10n.text("ios26.search.recent.blood_pressure"),
        L10n.text("ios26.search.recent.medication"),
        L10n.text("ios26.search.recent.reports")
    ]
    private let suggestions = [
        L10n.text("ios26.search.suggestion.family"),
        L10n.text("ios26.search.suggestion.science"),
        L10n.text("ios26.search.suggestion.chat")
    ]

    private var filteredItems: [String] {
        let allItems = recentSearches + suggestions
        guard !query.isEmpty else { return allItems }
        return allItems.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section(L10n.text("ios26.search.section.recent")) {
                        ForEach(recentSearches, id: \.self) { item in
                            Text(item)
                        }
                    }
                    Section(L10n.text("ios26.search.section.suggestions")) {
                        ForEach(suggestions, id: \.self) { item in
                            Text(item)
                        }
                    }
                } else {
                    ForEach(filteredItems, id: \.self) { item in
                        Text(item)
                    }
                }
            }
            .navigationTitle(L10n.text("tab.search"))
            .searchable(text: $query, prompt: L10n.text("ios26.search.prompt"))
        }
    }
}
