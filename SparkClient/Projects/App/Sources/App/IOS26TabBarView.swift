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
    @Environment(\.hospitalCare) private var hospitalCareDependencies

    @State private var showsDeviceAccountUpgradeSheet = false
    @State private var showsChatNoModelAlert = false
    @State private var showsChatAPIKeysSettingsSheet = false
    @State private var pendingKnowledgeDetailDocumentID: UUID?
    @State private var homeSafeAreaRefreshRevision = 0

    /// 当前布局下实际渲染的根 Tab 集合：classic 含饮食/运动独立 Tab，dashboard 含设置 Tab。
    private var visibleTabs: Set<AppRouteStore.RootTab> {
        if homeStylePreferenceStore.style == .classic {
            return [.healthHome, .hospital, .chat, .nutrition, .fitness]
        }
        return [.healthHome, .hospital, .chat, .settings]
    }

    private var destinationBuilder: MainTabRouteDestinationBuilder {
        MainTabRouteDestinationBuilder(
            routeStore: routeStore,
            session: session,
            homeDependencies: homeDependencies,
            knowledgeDependencies: knowledgeDependencies,
            popularScienceDependencies: popularScienceDependencies,
            hospitalCareDependencies: hospitalCareDependencies,
            homeViewModel: homeViewModel,
            knowledgeViewModel: knowledgeViewModel,
            taskManager: taskManager,
            chatStateStore: chatStateStore,
            chatListViewModel: chatListViewModel,
            chatDetailViewModel: chatDetailViewModel,
            chatAutoSmallTaskCoordinator: chatAutoSmallTaskCoordinator,
            accountManagementViewModel: accountManagementViewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            guideHomeDestinationBuilder: guideHomeDestinationBuilder,
            activeHomeFullScreenCover: $activeHomeFullScreenCover
        )
    }

    private var homeDashboardActionHandler: IOS26HomeDashboardActionHandler {
        IOS26HomeDashboardActionHandler(
            routeStore: routeStore,
            homeViewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            chatListViewModel: chatListViewModel,
            notificationClient: homeDependencies.notificationClient,
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

                Tab(L10n.text("tab.hospital"), systemImage: "cross.case.fill", value: AppRouteStore.RootTab.hospital) {
                    hospitalContainer
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

    // MARK: - CHAT-000057 D-015 消息分段未读角标

    /// 「消息」分段名称右侧的圆形数字角标；0 隐藏（返回空视图），>99 显示 99+。
    /// 不拦截点击（25.4：不影响分段文本的可点击区域）。
    @ViewBuilder
    private var messageSegmentUnreadBadge: some View {
        if let badgeText = unifiedUnreadBadgeText(chatListViewModel.messageSegmentUnreadCount) {
            Text(badgeText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.red))
                .offset(x: 6, y: -8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// CHAT-000057 25.4：分段选择器无障碍朗读；未读为 0 时不附加未读描述。
    private var messageSegmentPickerAccessibilityLabel: String {
        guard let badgeText = unifiedUnreadBadgeText(chatListViewModel.messageSegmentUnreadCount) else {
            return L10n.text("chat.segment.picker", fallback: "院内名医或消息")
        }
        if badgeText == "99+" {
            return L10n.text("chat.segment.messages.unread_overflow", fallback: "院内名医或消息，99 条以上未读消息")
        }
        return L10n.text("chat.segment.messages.unread", fallback: "院内名医或消息，\(badgeText) 条未读消息")
    }

    private var tabNavigationTitle: String {
        switch routeStore.selectedTab {
        case .healthHome:
            return L10n.text("ios26.home.title")
        case .hospital:
            return L10n.text("tab.hospital")
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
            if chatListViewModel.hospitalCatalogAvailable {
                ToolbarItem(placement: .principal) {
                    Picker("对话分段", selection: $chatListViewModel.chatListSegment) {
                        ForEach(ChatListSegment.allCases, id: \.self) { segment in
                            Text(segment.localizedTitle).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 220)
                    .fixedSize()
                    .accessibilityLabel(messageSegmentPickerAccessibilityLabel)
                    // CHAT-000057 D-015/25.4：「消息」分段名称右侧圆形数字角标；0 隐藏，>99 显示 99+。
                    .overlay(alignment: .topTrailing) {
                        messageSegmentUnreadBadge
                    }
                }
            }
            if chatListViewModel.hospitalCatalogAvailable == false || chatListViewModel.chatListSegment == .conversations {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createChatThread() }
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
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

    /// IOS26-TABBAR-000009：医院服务首页根 Tab 内容；Tab 常驻，返回时保留滚动位置（Q21）。
    @ViewBuilder
    private var hospitalContainer: some View {
        if let dependencies = hospitalCareDependencies {
            HospitalHomeView(
                dependencies: dependencies,
                homeDependencies: homeDependencies,
                onOpenReportInterpretation: {
                    // 复用既有报告解读快捷入口：新建会话 → 自动发送小任务 → 报告上传卡片。
                    homeDashboardActionHandler.handle(.reportInterpretation)
                },
                onOpenDirectory: { departmentID in
                    routeStore.route(to: .hospitalAgentDirectory(departmentID: departmentID))
                },
                onOpenThread: { threadID in
                    routeStore.route(to: .chatThread(threadID))
                },
                onOpenTelemedicine: {
                    routeStore.route(to: .hospitalConsultation(.departments))
                }
            )
        } else {
            VStack(spacing: 12) {
                Spacer()
                Text("医院服务暂不可用")
                    .font(.headline)
                Text("请稍后重试或检查网络连接")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
