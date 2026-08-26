import SwiftUI
import UIKit

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
    let guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder

    @ObservedObject private var homeStylePreferenceStore = HomeStylePreferenceStore.shared
    @ObservedObject private var homeSectionPreferenceStore = HomeSectionPreferenceStore.shared

    @State private var showsDeviceAccountUpgradeSheet = false
    @State private var showsChatNoModelAlert = false
    @State private var showsChatAPIKeysSettingsSheet = false
    @State private var pendingKnowledgeDetailDocumentID: UUID?
    @State private var homeSafeAreaRefreshRevision = 0

    /// 当前布局下实际渲染的根 Tab 集合：classic 含饮食/运动独立 Tab，dashboard 含设置 Tab。
    private var visibleTabs: Set<AppRouteStore.RootTab> {
        if homeStylePreferenceStore.style == .classic {
            return [.healthHome, .chat, .nutrition, .fitness]
        }
        return [.healthHome, .chat, .settings]
    }

    private var destinationBuilder: MainTabRouteDestinationBuilder {
        MainTabRouteDestinationBuilder(
            routeStore: routeStore,
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
            aiSettingsViewModel: aiSettingsViewModel,
            guideHomeDestinationBuilder: guideHomeDestinationBuilder
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
        CompatibleRouteNavigationContainer(path: routePath(routeStore.selectedTab)) {
            TabView(selection: $routeStore.selectedTab) {
                Tab(L10n.text("tab.health"), systemImage: "heart.fill", value: AppRouteStore.RootTab.healthHome) {
                    if homeStylePreferenceStore.style == .dashboard {
                        homeContainer
                    } else {
                        healthContainer
                    }
                }

                if homeStylePreferenceStore.style == .classic {
                    Tab(L10n.text("tab.nutrition"), systemImage: "fork.knife", value: AppRouteStore.RootTab.nutrition) {
                        nutritionContainer
                    }

                    Tab(L10n.text("tab.fitness"), systemImage: "figure.run", value: AppRouteStore.RootTab.fitness) {
                        fitnessContainer
                    }
                } else {
                    Tab(L10n.text("tab.settings"), systemImage: "gearshape.fill", value: AppRouteStore.RootTab.settings) {
                        settingsContainer
                    }

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

            
                Tab(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill", value: AppRouteStore.RootTab.chat, role: .search) {
                    chatContainer
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
//            .navigationTitle(tabNavigationTitle)
            .navigationBarTitleDisplayMode(tabTitleDisplayMode)
            .toolbar { tabToolbar }
            .navigationDestination(isPresented: Binding(
                get: { pendingKnowledgeDetailDocumentID != nil },
                set: { active in
                    if active == false {
                        pendingKnowledgeDetailDocumentID = nil
                    }
                }
            )) {
                if let id = pendingKnowledgeDetailDocumentID {
                    KnowledgeDocumentDetailView(
                        dependencies: knowledgeDependencies,
                        viewModel: knowledgeViewModel,
                        documentID: id
                    )
                    .hidesMainTabBarWhenPushed()
                }
            }
        } destination: { route in
            destinationBuilder.destination(route)
        }
        .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
            LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
        }
        .alert(L10n.text("chat.list.no_available_model.title"), isPresented: $showsChatNoModelAlert) {
            Button(L10n.text("chat.list.no_available_model.action")) {
                showsChatAPIKeysSettingsSheet = true
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("chat.list.no_available_model.message"))
        }
        .sheet(isPresented: $showsChatAPIKeysSettingsSheet) {
            NavigationView {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                showsChatAPIKeysSettingsSheet = false
                            }
                        }
                    }
            }
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
            // 持久化恢复的 tab 在当前布局不可见时兜底（IOS26-TABBAR-000007）
            routeStore.ensureSelectedTabIsVisible(visibleTabs: visibleTabs)
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
        }
        .onDisappear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = false }
        }
        .onChange(of: homeStylePreferenceStore.style) { _, _ in
            // 样式切换导致当前 Tab 不可见时立即兜底，并同步持久化值
            routeStore.ensureSelectedTabIsVisible(visibleTabs: visibleTabs)
        }
        .onChange(of: routeStore.routes(for: .healthHome).isEmpty) { wasEmpty, isEmpty in
            guard wasEmpty == false, isEmpty else { return }
            homeSafeAreaRefreshRevision += 1
        }
    }

    private var tabNavigationTitle: String {
        switch routeStore.selectedTab {
        case .healthHome:
            return L10n.text("ios26.home.title")
        case .nutrition:
            return L10n.text("nutrition.home.title")
        case .fitness:
            return L10n.text("fitness.home.title")
        case .knowledge:
            return L10n.text("knowledge.library.title")
        case .settings:
            return L10n.text("settings.title")
        case .chat:
            return L10n.text("chat.title")
        default:
            return ""
        }
    }

    private var tabTitleDisplayMode: NavigationBarItem.TitleDisplayMode {
        switch routeStore.selectedTab {
        case .chat:
            return .inline
        default:
            return .inline
//            return .large
        }
    }

    @ToolbarContentBuilder
    private var tabToolbar: some ToolbarContent {
        switch routeStore.selectedTab {
        case .healthHome:
            ToolbarItem(placement: .topBarLeading) {
                memberSelectorHeader
            }
            healthHomeTrailingToolbar
        case .chat:
            ToolbarItem(placement: .topBarLeading) {
                MainNavigationLink {
                    KnowledgeLibraryView(
                        dependencies: knowledgeDependencies,
                        viewModel: knowledgeViewModel
                    )
                } label: {
                    Image(systemName: "backpack.fill")
                }
                .accessibilityLabel(L10n.text("knowledge.library.title"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await createChatThread() }
                } label: {
                    Image(systemName: "plus.bubble")
                }
            }
        case .nutrition:
            ToolbarItem(placement: .topBarTrailing) {
                MainNavigationLink {
                    NutritionGoalView(
                        goalUseCase: homeDependencies.nutritionDependencies.goalUseCase,
                        memberID: nutritionResolvedMemberID,
                        member: homeDependencies.nutritionDependencies.memberContextStore.context.selectedMember,
                        onSaved: {
                            NotificationCenter.default.post(name: .nutritionGoalDidSave, object: nil)
                        }
                    )
                } label: {
                    Image(systemName: "target")
                }
                .disabled(nutritionResolvedMemberID == 0)
                .accessibilityLabel(L10n.text("nutrition.goal.title", fallback: "我的目标"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                MainNavigationLink {
                    NutritionHistoryView(
                        mealRecordUseCase: homeDependencies.nutritionDependencies.mealRecordUseCase,
                        memberID: nutritionResolvedMemberID
                    )
                } label: {
                    Text(L10n.text("nutrition.history.entry"))
                }
            }
        case .knowledge:
            ToolbarItemGroup(placement: .topBarTrailing) {
                MainNavigationLink {
                    KnowledgeSearchView(
                        dependencies: knowledgeDependencies,
                        viewModel: knowledgeViewModel
                    )
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                Button {
                    Task { await createKnowledgeDocumentAndNavigate() }
                } label: {
                    Image(systemName: "plus")
                }
            }
        default:
            ToolbarItem(placement: .automatic) {
                EmptyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var healthHomeTrailingToolbar: some ToolbarContent {
        switch homeSectionPreferenceStore.section {
        case .dashboard:
            ToolbarItem(placement: .topBarTrailing) {
                MainNavigationLink {
                    SettingsView(
                        viewModel: settingsViewModel,
                        aiSettingsViewModel: aiSettingsViewModel,
                        accountManagementViewModel: accountManagementViewModel,
                        versionUpdateCoordinator: versionUpdateCoordinator,
                        memberContextStore: homeDependencies.memberContextStore,
                        session: session,
                        showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet
                    )
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(L10n.text("settings.title"))
            }
        case .nutrition:
            ToolbarItem(placement: .topBarTrailing) {
                MainNavigationLink {
                    NutritionGoalView(
                        goalUseCase: homeDependencies.nutritionDependencies.goalUseCase,
                        memberID: nutritionResolvedMemberID,
                        member: homeDependencies.nutritionDependencies.memberContextStore.context.selectedMember,
                        onSaved: {
                            NotificationCenter.default.post(name: .nutritionGoalDidSave, object: nil)
                        }
                    )
                } label: {
                    Image(systemName: "target")
                }
                .disabled(nutritionResolvedMemberID == 0)
                .accessibilityLabel(L10n.text("nutrition.goal.title", fallback: "我的目标"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                MainNavigationLink {
                    NutritionHistoryView(
                        mealRecordUseCase: homeDependencies.nutritionDependencies.mealRecordUseCase,
                        memberID: nutritionResolvedMemberID
                    )
                } label: {
                    Text(L10n.text("nutrition.history.entry"))
                }
            }
        case .fitness:
            ToolbarItem(placement: .topBarTrailing) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var memberSelectorHeader: some View {
        let members = homeViewModel.dashboard?.members ?? homeViewModel.memberContextStoreForBinding.context.members
        let resolvedMember: Member? = {
            if let selectedMemberID = homeViewModel.selectedMemberID {
                return members.first(where: { $0.id == selectedMemberID }) ?? members.first
            }
            return members.first
        }()

        if let member = resolvedMember, members.isEmpty == false {
            MemberProfileBindingMenu(
                memberContextStore: homeViewModel.memberContextStoreForBinding,
                selectedMemberID: homeViewModel.selectedMemberID,
                onSelect: { memberID in
                    guard let memberID, memberID != homeViewModel.selectedMemberID else { return }
                    homeViewModel.selectMember(memberID)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            ) {
                MemberSelectorChip(
                    member: member,
                    badgeText: MemberSelectorChip.badgeText(for: member),
                    isSelected: false,
                    variant: .compactToolbar,
                    onSelect: {},
                    onViewDetail: {},
                    onShare: {}
                )
            }
            .accessibilityLabel(
                String(
                    format: L10n.text("home.medical.medication_execution.member_switch.accessibility"),
                    member.name
                )
            )
        }
    }

    private func createChatThread() async {
        guard await chatDetailViewModel.hasAvailableChatModel() else {
            showsChatNoModelAlert = true
            return
        }
        pushAdapter.requestAuthorizationIfNotDetermined()
        await chatListViewModel.createThread()
        guard let threadID = chatStateStore.selectedThreadID else { return }
        routeStore.route(to: .chatThread(threadID))
    }

    private var nutritionResolvedMemberID: Int {
        homeDependencies.nutritionDependencies.memberContextStore.context.selectedMemberID ?? 0
    }

    private func createKnowledgeDocumentAndNavigate() async {
        guard let document = await knowledgeViewModel.createNewDocument() else { return }
        pendingKnowledgeDetailDocumentID = document.id
    }

    private var homeContainer: some View {
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
            currentSection: $homeSectionPreferenceStore.section,
            safeAreaRefreshRevision: homeSafeAreaRefreshRevision,
            activeFullScreenCover: $activeHomeFullScreenCover
        )
        // The system TabView owns the bottom safe area. Apply the policy at the
        // tab-content boundary so it is recalculated correctly after a pushed
        // destination temporarily hides, then restores, the main tab bar.
//        .ignoresSafeArea(.container, edges: .bottom)
//        .toolbar(.visible, for: .tabBar)
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
                pushAdapter: pushAdapter,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder,
                onPresentChat: { request in
                    routeStore.route(to: .automaticChatThread(request.threadID))
                }
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }

    private var healthContainer: some View {
        HealthHomeView(
            dependencies: homeDependencies,
            viewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: launchIntentCoordinator,
            session: session,
            taskManager: taskManager,
            chatListViewModel: chatListViewModel,
            deepTutorChatViewModel: deepTutorChatViewModel,
            autoSmallTaskRegistry: autoSmallTaskRegistry,
            autoSmallTaskIntentStore: chatAutoSmallTaskIntentStore,
            activeFullScreenCover: $activeHomeFullScreenCover
        )
    }

    private var nutritionContainer: some View {
        NutritionHomeView(dependencies: homeDependencies.nutritionDependencies)
    }

    private var fitnessContainer: some View {
        FitnessHomeView(dependencies: homeDependencies.fitnessDependencies)
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
        KnowledgeLibraryView(
            dependencies: knowledgeDependencies,
            viewModel: knowledgeViewModel
        )
    }

    private var settingsContainer: some View {
        SettingsView(
            viewModel: settingsViewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            accountManagementViewModel: accountManagementViewModel,
            versionUpdateCoordinator: versionUpdateCoordinator,
            memberContextStore: homeDependencies.memberContextStore,
            session: session,
            showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet
        )
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
