import SwiftUI

/// 主 Tab 导航栈共享 route destination，供 `MainTabCoordinatorView` 与 `IOS26TabBarView` 复用。
@MainActor
struct MainTabRouteDestinationBuilder {
    let session: UserSession
    let homeDependencies: HomeFeatureDependencies
    let knowledgeDependencies: KnowledgeFeatureDependencies
    let popularScienceDependencies: PopularScienceFeatureDependencies
    let homeViewModel: HomeViewModel
    let knowledgeViewModel: KnowledgeLibraryViewModel
    let taskManager: TaskManager
    let chatStateStore: ChatStateStore
    let chatListViewModel: ChatListViewModel
    let chatDetailViewModel: ChatDetailViewModel
    let chatAutoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator?
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let accountManagementViewModel: AccountManagementViewModel
    let aiSettingsViewModel: AISettingsViewModel

    @ViewBuilder
    func destination(_ route: AppRoute) -> some View {
        switch route {
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
                autoSmallTaskCoordinator: chatAutoSmallTaskCoordinator
            )
            .task(id: threadID) {
                await chatListViewModel.selectAndPrepare(threadID: threadID)
                await chatDetailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
            }
        case .deepTutorThread(let conversationID):
            DeepTutorChatPage(
                conversationID: conversationID,
                viewModel: deepTutorChatViewModel,
                aiSettingsViewModel: aiSettingsViewModel
            )
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
        case .taskDetail(let memberID, let taskID):
            TaskDetailView(
                memberID: memberID,
                taskManager: taskManager,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskID: taskID
            )
        case .popularScienceArticle(let articleID):
            PopularScienceArticleDetailView(
                viewModel: popularScienceDependencies.makeDetailViewModel(articleID)
            )
        case .home, .knowledge, .nutrition, .chatList, .popularScience, .settings, .deepTutorList:
            EmptyView()
        }
    }
}
