import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var showsHospitalNoticeAlert = false
    @State private var homeSafeAreaRefreshRevision = 0

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

    private var actionHandler: IOS26HomeDashboardActionHandler {
        IOS26HomeDashboardActionHandler(
            routeStore: homeDependencies.routeStore,
            homeViewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            chatListViewModel: chatListViewModel,
            notificationClient: homeDependencies.notificationClient,
            autoSmallTaskRegistry: autoSmallTaskRegistry,
            autoSmallTaskIntentStore: chatAutoSmallTaskIntentStore,
            ownerAccountID: session.accountID
        )
    }

    private var usesDashboardHomeStyle: Bool {
        homeStylePreferenceStore.style == .dashboard
    }

    private var visibleTabs: Set<AppRouteStore.RootTab> {
        if usesDashboardHomeStyle {
            return [.healthHome, .hospital, .chat, .settings]
        }
        return [.healthHome, .hospital, .chat, .nutrition, .fitness, .settings]
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: routePath(routeStore.selectedTab)) {
            TabView(selection: $routeStore.selectedTab) {
                healthHomeTab
                hospitalTab
                chatTab
                if usesDashboardHomeStyle == false {
                    nutritionTab
                    fitnessTab
                }
                settingsTab
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { tabToolbar }
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
        // IOS26-TABBAR-000009：医院 Tab 右上角通知占位，点击提示"功能正在实现"（原型 §3）。
        .alert("医院通知", isPresented: $showsHospitalNoticeAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("功能正在实现，敬请期待")
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
        .onChange(of: homeStylePreferenceStore.style) { _ in
            ensureSelectedTabIsVisible()
        }
        .onChange(of: routeStore.selectedTab) { _ in
            ensureSelectedTabIsVisible()
        }
        .onChange(of: routeStore.routes(for: .healthHome).isEmpty) { isEmpty in
            guard isEmpty else { return }
            homeSafeAreaRefreshRevision += 1
        }
        .onAppear {
            ensureSelectedTabIsVisible()
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
        }
        .onDisappear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = false }
        }
    }

    @ViewBuilder
    private var healthHomeTab: some View {
        Group {
            if usesDashboardHomeStyle {
                dashboardHomeContainer
            } else {
                classicHomeContainer
            }
        }
        .tabItem {
            Label(L10n.text("tab.health"), systemImage: "heart.fill")
        }
        .tag(AppRouteStore.RootTab.healthHome)
    }

    @ViewBuilder
    private var dashboardHomeContainer: some View {
        IOS26HomeView(
            dependencies: homeDependencies,
            viewModel: homeViewModel,
            taskManager: taskManager,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: launchIntentCoordinator,
            session: session,
            actionHandler: actionHandler,
            chatListViewModel: chatListViewModel,
            currentSection: $homeSectionPreferenceStore.section,
            safeAreaRefreshRevision: homeSafeAreaRefreshRevision,
            activeFullScreenCover: $activeHomeFullScreenCover
        )
        
    }

    private var classicHomeContainer: some View {
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

    /// IOS26-TABBAR-000009：医院服务首页根 Tab（健康｜医院｜消息｜设置）。
    /// Tab 内容常驻 TabView，离开医院 Tab 再返回时保留滚动位置与页面状态（Q21）。
    @ViewBuilder
    private var hospitalTab: some View {
        Group {
            if let dependencies = hospitalCareDependencies {
                HospitalHomeView(
                    dependencies: dependencies,
                    homeDependencies: homeDependencies,
                    onOpenReportInterpretation: {
                        // 复用既有报告解读快捷入口：新建会话 → 自动发送小任务 → 报告上传卡片。
                        actionHandler.handle(.reportInterpretation)
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
        .tabItem {
            Label(L10n.text("tab.hospital"), systemImage: "cross.case.fill")
        }
        .tag(AppRouteStore.RootTab.hospital)
    }

    private var chatTab: some View {
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
        .tabItem {
            Label(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
        }
        .tag(AppRouteStore.RootTab.chat)
    }

    private var nutritionTab: some View {
        NutritionHomeView(
            dependencies: homeDependencies.nutritionDependencies,
            showsNavigationChrome: false
        )
        .tabItem {
            Label(L10n.text("tab.nutrition"), systemImage: "fork.knife")
        }
        .tag(AppRouteStore.RootTab.nutrition)
    }

    private var fitnessTab: some View {
        FitnessHomeView(
            dependencies: homeDependencies.fitnessDependencies,
            showsNavigationChrome: false
        )
        .tabItem {
            Label(L10n.text("tab.fitness"), systemImage: "figure.run")
        }
        .tag(AppRouteStore.RootTab.fitness)
    }

    private var settingsTab: some View {
        SettingsView(
            viewModel: settingsViewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            accountManagementViewModel: accountManagementViewModel,
            versionUpdateCoordinator: versionUpdateCoordinator,
            memberContextStore: homeDependencies.memberContextStore,
            session: session,
            showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet
        )
        .tabItem {
            Label(L10n.text("tab.settings"), systemImage: "gearshape.fill")
        }
        .tag(AppRouteStore.RootTab.settings)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await createChatThread() }
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .accessibilityLabel(L10n.text("chat.thread.new", fallback: "新建对话"))
            }
        case .nutrition:
            nutritionToolbarItems
        case .hospital:
            // 医院首页右上角通知入口，样式与其他 Tab 头部保持一致（原型 §2.1 铃铛）。
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsHospitalNoticeAlert = true
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("医院通知")
            }
        default:
            ToolbarItem(placement: .automatic) {
                EmptyView()
            }
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

    @ToolbarContentBuilder
    private var healthHomeTrailingToolbar: some ToolbarContent {
        if usesDashboardHomeStyle, homeSectionPreferenceStore.section == .nutrition {
            nutritionToolbarItems
        } else if usesDashboardHomeStyle, homeSectionPreferenceStore.section == .fitness {
            ToolbarItem(placement: .topBarTrailing) {
                EmptyView()
            }
        } else {
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
        }
    }

    @ToolbarContentBuilder
    private var nutritionToolbarItems: some ToolbarContent {
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
                    triggerHaptic(style: .light)
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

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }

    private func ensureSelectedTabIsVisible() {
        routeStore.ensureSelectedTabIsVisible(visibleTabs: visibleTabs)
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
