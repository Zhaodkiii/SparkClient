import SwiftUI

/// 主 Tab 导航栈共享路由目的地构建器，供 `MainTabCoordinatorView` 与 `IOS26TabBarView` 复用，
/// 统一处理主 Tab 内所有导航路由对应的页面构建。
@MainActor
struct MainTabRouteDestinationBuilder {
    let routeStore: AppRouteStore
    /// 用户会话信息，管理登录状态与用户身份
    let session: UserSession
    /// 首页功能模块依赖容器
    let homeDependencies: HomeFeatureDependencies
    /// 知识库功能模块依赖容器
    let knowledgeDependencies: KnowledgeFeatureDependencies
    /// 科普文章功能模块依赖容器
    let popularScienceDependencies: PopularScienceFeatureDependencies
    /// 医院功能模块依赖容器（IOS26-TABBAR-000009 医院首页与目录路由）；注入失败时医院路由降级为空视图。
    var hospitalCareDependencies: HospitalCareFeatureDependencies? = nil
    /// 首页视图模型
    let homeViewModel: HomeViewModel
    /// 知识库页面视图模型
    let knowledgeViewModel: KnowledgeLibraryViewModel
    /// 任务管理器，统一管理健康任务的调度与执行
    let taskManager: TaskManager
    /// 聊天状态存储，维护聊天全局状态
    let chatStateStore: ChatStateStore
    /// 聊天列表视图模型
    let chatListViewModel: ChatListViewModel
    /// 聊天详情页视图模型
    let chatDetailViewModel: ChatDetailViewModel
    /// 聊天自动小任务协调器，处理对话中的自动化小任务，可为空
    let chatAutoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator?
    /// 账户管理页面视图模型
    let accountManagementViewModel: AccountManagementViewModel
    /// AI 设置页面视图模型
    let aiSettingsViewModel: AISettingsViewModel
    /// 引导卡片滑块 → 健康首页 destination（CHAT-000025）；nil 时滑块降级为纯展示。
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil
    /// 医院问诊卡片/详情打开对话时使用宿主 fullScreenCover，避免跳进对话 Tab。
    var activeHomeFullScreenCover: Binding<HomeFullScreenCover?> = .constant(nil)

    /// 根据指定路由构建对应的目标视图
    /// - Parameter route: 应用导航路由枚举
    /// - Returns: 路由对应的 SwiftUI 视图
    @ViewBuilder
    func destination(_ route: AppRoute) -> some View {
        switch route {
        /// 普通聊天会话页面，传入会话ID并在页面出现时准备数据与加载消息
        case .chatThread(let threadID):
            ChatView(
                threadID: threadID,
                stateStore: chatStateStore,
                listViewModel: chatListViewModel,
                detailViewModel: chatDetailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                autoSmallTaskCoordinator: chatAutoSmallTaskCoordinator,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder
            )
            .task(id: threadID) {
                await chatListViewModel.selectAndPrepare(threadID: threadID)
                await chatDetailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
            }
        case .automaticChatThread(let threadID):
            ChatView(
                threadID: threadID,
                stateStore: chatStateStore,
                listViewModel: chatListViewModel,
                detailViewModel: chatDetailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                autoSmallTaskCoordinator: chatAutoSmallTaskCoordinator,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder,
                leadingAction: .home,
                onClose: {
                    routeStore.route(to: .home, replaceStack: true)
                }
            )
            .task(id: threadID) {
                await chatListViewModel.selectAndPrepare(threadID: threadID)
                await chatDetailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
            }
        /// AI 设置页面
        case .aiSettings:
            AISettingsView(viewModel: aiSettingsViewModel)
        /// 账户管理页面
        case .accountManagement:
            AccountManagementView(viewModel: accountManagementViewModel, session: session)
        /// 首页医疗列表页面，支持指定列表路由和用药聚焦项
        case .homeMedicalList(let listRoute, let medicationFocus):
            HomeMedicalRouteSupport.medicalListView(
                route: listRoute,
                medicationFocus: medicationFocus,
                homeViewModel: homeViewModel,
                dependencies: homeDependencies,
                session: session
            )
        /// 首页家庭药箱页面，传入成员ID
        case .homeFamilyMedicineCabinet(let memberID):
            HomeMedicalRouteSupport.familyMedicineCabinetView(
                memberID: memberID,
                homeViewModel: homeViewModel,
                dependencies: homeDependencies
            )
        /// 任务详情页面，传入成员ID和任务ID
        case .taskDetail(let memberID, let taskID):
            TaskDetailView(
                memberID: memberID,
                taskManager: taskManager,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskID: taskID
            )
        /// 科普文章详情页面，通过依赖容器创建对应文章的视图模型
        case .popularScienceArticle(let articleID):
            PopularScienceArticleDetailView(
                viewModel: popularScienceDependencies.makeDetailViewModel(articleID)
            )
        /// 医院医生智能体目录（IOS26-TABBAR-000009）：可携带首页固定科室的初始筛选；
        /// 点击医生卡片创建/继续医院会话后，按既有契约路由到对话 Tab 的 ChatView。
        case .hospitalAgentDirectory(let departmentID):
            if let hospitalCareDependencies {
                HospitalAgentDirectoryView(
                    dependencies: hospitalCareDependencies,
                    memberContextStore: homeDependencies.memberContextStore,
                    sessionStore: homeDependencies.sessionStore,
                    initialDepartmentID: departmentID,
                    onOpenThread: { threadID in
                        routeStore.route(to: .chatThread(threadID))
                    }
                )
            } else {
                EmptyView()
            }
        /// 线上问诊流程（科室选择 → 医生选择 → 问诊材料）；提交后回到最近问诊。
        case .hospitalConsultation(let focus):
            if let hospitalCareDependencies {
                ConsultFlowView(
                    dependencies: hospitalCareDependencies,
                    memberContextStore: homeDependencies.memberContextStore,
                    sessionStore: homeDependencies.sessionStore,
                    routeStore: routeStore,
                    focus: focus,
                    onOpenThread: { threadID in
                        activeHomeFullScreenCover.wrappedValue = .chat(
                            threadID: threadID,
                            source: .hospitalConsultation
                        )
                    }
                )
            } else {
                EmptyView()
            }
        /// 线上问诊第二步：科室选择后 push 的独立医生选择页。
        case .hospitalDoctorSelect(let hospitalID, let departmentID):
            if let hospitalCareDependencies {
                ConsultDoctorSelectRouteView(
                    dependencies: hospitalCareDependencies,
                    hospitalID: hospitalID,
                    departmentID: departmentID,
                    memberContextStore: homeDependencies.memberContextStore,
                    sessionStore: homeDependencies.sessionStore,
                    routeStore: routeStore
                )
            } else {
                EmptyView()
            }
        /// 线上问诊第三步：点击医生后 push 的问诊材料填写页；提交成功后回到最近问诊。
        case .hospitalConsultForm(let agentID):
            if let hospitalCareDependencies {
                ConsultFormRouteView(
                    dependencies: hospitalCareDependencies,
                    agentID: agentID,
                    memberContextStore: homeDependencies.memberContextStore,
                    sessionStore: homeDependencies.sessionStore,
                    onSubmitted: { _ in
                        routeStore.route(to: .hospitalConsultation(.recent), replaceStack: true)
                    }
                )
            } else {
                EmptyView()
            }
        /// Tab 根页面路由，无需构建导航目的地，返回空视图
        case .home, .knowledge, .nutrition, .fitness, .chatList, .popularScience, .settings, .hospitalHome:
            EmptyView()
        }
    }
}
