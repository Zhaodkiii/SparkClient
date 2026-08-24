import SwiftUI

/// 已登录主界面中间页：集中选择 iOS 26 / 经典 Tab，并统一承载首页 sheet 与 fullScreenCover。
struct SignedInMainTabHostView: View {
    let session: UserSession
    let mainTab: MainTabDependencies
    @ObservedObject private var homeViewModel: HomeViewModel

    @State private var activeHomeFullScreenCover: HomeFullScreenCover?
    @State private var addMemberNearbyTransport = NearbyShareTransport()
    @State private var pendingHealthResourceConversationRequest: HealthResourceConversationRequest?
    @State private var showNoAvailableHealthChatModelAlert = false
    @State private var isPreparingHealthResourceConversation = false
    
    init(session: UserSession, mainTab: MainTabDependencies) {
        self.session = session
        self.mainTab = mainTab
        self._homeViewModel = ObservedObject(wrappedValue: mainTab.homeViewModel)
    }

    var body: some View {
        tabContent
            .sheet(item: $homeViewModel.activeSheet) { sheet in
                homeSheetContent(sheet)
            }
            .fullScreenCover(item: $activeHomeFullScreenCover) { cover in
                homeFullScreenCoverContent(cover)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .healthResourceConversationRequested)
            ) { notification in
                guard let request = notification.object as? HealthResourceConversationRequest else {
                    return
                }
                handleHealthResourceConversationRequest(request)
            }
            .alert(
                L10n.text("chat.list.no_available_model.title"),
                isPresented: $showNoAvailableHealthChatModelAlert
            ) {
                Button(L10n.text("chat.list.no_available_model.action")) {
                    homeViewModel.activeSheet = .apiKeysSettings
                }
                Button(L10n.text("common.cancel"), role: .cancel) {
                    pendingHealthResourceConversationRequest = nil
                }
            } message: {
                Text(L10n.text("chat.list.no_available_model.message"))
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        
        
        if #available(iOS 28.0, *) {
            IOS26TabBarView(
                session: session,
                routeStore: mainTab.routeStore,
                homeDependencies: mainTab.homeDependencies,
                knowledgeDependencies: mainTab.knowledgeDependencies,
                popularScienceDependencies: mainTab.popularScienceDependencies,
                taskManager: mainTab.taskManager,
                homeViewModel: mainTab.homeViewModel,
                medicalDocumentUploadViewModel: mainTab.medicalDocumentUploadViewModel,
                knowledgeViewModel: mainTab.knowledgeViewModel,
                popularScienceViewModel: mainTab.popularScienceViewModel,
                chatStateStore: mainTab.chatStateStore,
                chatListViewModel: mainTab.chatListViewModel,
                chatDetailViewModel: mainTab.chatDetailViewModel,
                chatAutoSmallTaskIntentStore: mainTab.chatAutoSmallTaskIntentStore,
                chatAutoSmallTaskCoordinator: mainTab.chatAutoSmallTaskCoordinator,
                autoSmallTaskRegistry: mainTab.autoSmallTaskRegistry,
                deepTutorChatViewModel: mainTab.deepTutorChatViewModel,
                settingsViewModel: mainTab.settingsViewModel,
                accountManagementViewModel: mainTab.accountManagementViewModel,
                aiSettingsViewModel: mainTab.aiSettingsViewModel,
                versionUpdateCoordinator: mainTab.versionUpdateCoordinator,
                upgradeLoginViewModel: mainTab.upgradeLoginViewModel,
                pushAdapter: mainTab.pushAdapter,
                externalMedicalDocumentImportCoordinator: mainTab.externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: mainTab.launchIntentCoordinator,
                activeHomeFullScreenCover: $activeHomeFullScreenCover
            )
        } else {
            MainTabCoordinatorView(
                session: session,
                routeStore: mainTab.routeStore,
                homeDependencies: mainTab.homeDependencies,
                knowledgeDependencies: mainTab.knowledgeDependencies,
                popularScienceDependencies: mainTab.popularScienceDependencies,
                taskManager: mainTab.taskManager,
                homeViewModel: mainTab.homeViewModel,
                medicalDocumentUploadViewModel: mainTab.medicalDocumentUploadViewModel,
                knowledgeViewModel: mainTab.knowledgeViewModel,
                popularScienceViewModel: mainTab.popularScienceViewModel,
                chatStateStore: mainTab.chatStateStore,
                chatListViewModel: mainTab.chatListViewModel,
                chatDetailViewModel: mainTab.chatDetailViewModel,
                chatAutoSmallTaskIntentStore: mainTab.chatAutoSmallTaskIntentStore,
                chatAutoSmallTaskCoordinator: mainTab.chatAutoSmallTaskCoordinator,
                autoSmallTaskRegistry: mainTab.autoSmallTaskRegistry,
                deepTutorChatViewModel: mainTab.deepTutorChatViewModel,
                settingsViewModel: mainTab.settingsViewModel,
                accountManagementViewModel: mainTab.accountManagementViewModel,
                aiSettingsViewModel: mainTab.aiSettingsViewModel,
                versionUpdateCoordinator: mainTab.versionUpdateCoordinator,
                upgradeLoginViewModel: mainTab.upgradeLoginViewModel,
                pushAdapter: mainTab.pushAdapter,
                externalMedicalDocumentImportCoordinator: mainTab.externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: mainTab.launchIntentCoordinator,
                activeHomeFullScreenCover: $activeHomeFullScreenCover
            )
        }
    }

}

private extension SignedInMainTabHostView {
    @ViewBuilder
    func homeSheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .addMember(let addMemberSheet):
            CompatibleNavigationContainer {
                switch addMemberSheet {
                case .create(let pendingTicket):
                    AddFamilyMemberView(
                        mode: .create,
                        store: mainTab.homeViewModel.memberContextStoreForBinding,
                        shareUseCase: mainTab.homeDependencies.shareMemberUseCase,
                        inviteUseCase: mainTab.homeDependencies.memberInviteUseCase,
                        nearbyTransport: addMemberNearbyTransport,
                        initialPendingTicket: pendingTicket,
                        onBindingAccepted: {
                            Task {
                                await mainTab.homeViewModel.refresh()
                                await mainTab.homeViewModel.fetchPendingInvitesIfNeeded()
                            }
                        },
                        onCreatedMemberCompleted: { member in
                            mainTab.homeViewModel.selectMember(member.id)
                        },
                        homeDependencies: mainTab.homeDependencies
                    )
                case .edit(let member):
                    AddFamilyMemberView(
                        mode: .edit(member),
                        store: mainTab.homeViewModel.memberContextStoreForBinding
                    )
                case .acceptInvite(let inviteID, let preview):
                    AddFamilyMemberView(
                        mode: .acceptInvite(inviteID: inviteID, preview: preview),
                        store: mainTab.homeViewModel.memberContextStoreForBinding,
                        inviteUseCase: mainTab.homeDependencies.memberInviteUseCase,
                        onBindingAccepted: {
                            Task {
                                await mainTab.homeViewModel.refresh()
                                await mainTab.homeViewModel.fetchPendingInvitesIfNeeded()
                            }
                        }
                    )
                }
            }

        case .pendingInvites:
            PendingMemberInvitesView(viewModel: mainTab.homeViewModel)

        case .memberModuleSetup(let member):
            MemberSetupFlowView(
                mode: .maintain(member),
                store: mainTab.homeViewModel.memberContextStoreForBinding,
                homeDependencies: mainTab.homeDependencies,
                onMemberCreated: { member in
                    mainTab.homeViewModel.selectMember(member.id)
                    Task { await mainTab.homeViewModel.refresh() }
                }
            )

        case .share(let member):
            ShareSheet(
                member: member,
                shareUseCase: mainTab.homeDependencies.shareMemberUseCase,
                inviteUseCase: mainTab.homeDependencies.memberInviteUseCase
            )

        case .taskCenter:
            CompatibleNavigationContainer {
                TaskCenterViewController(
                    memberID: mainTab.homeViewModel.selectedMemberID,
                    knowledgeDependencies: mainTab.knowledgeDependencies,
                    taskManager: mainTab.taskManager,
                    knowledgeViewModel: mainTab.knowledgeViewModel
                )
            }

        case .apiKeysSettings:
            CompatibleNavigationContainer {
                APIKeysSettingsView(viewModel: mainTab.aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                homeViewModel.activeSheet = nil
                            }
                        }
                    }
            }
            .onDisappear {
                guard pendingHealthResourceConversationRequest != nil else { return }
                Task { await preparePendingHealthResourceConversation() }
            }
        }
    }

    @ViewBuilder
    func homeFullScreenCoverContent(_ cover: HomeFullScreenCover) -> some View {
        switch cover {
        case .medicalDocumentUpload:
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: mainTab.medicalDocumentUploadViewModel,
                    aiSettingsViewModel: mainTab.aiSettingsViewModel
                )
            }

        case .customCamera:
            CustomCameraHomeView {
                activeHomeFullScreenCover = nil
            }

        case .memberDetail(let memberID):
            memberDetailFullScreenCover(memberID: memberID)

        case .chat(let threadID):
            chatFullScreenCover(threadID: threadID)
        }
    }

    @ViewBuilder
    private func chatFullScreenCover(threadID: UUID) -> some View {
        CompatibleNavigationContainer {
            ChatView(
                threadID: threadID,
                stateStore: mainTab.chatStateStore,
                listViewModel: mainTab.chatListViewModel,
                detailViewModel: mainTab.chatDetailViewModel,
                knowledgeDependencies: mainTab.knowledgeDependencies,
                knowledgeViewModel: mainTab.knowledgeViewModel,
                taskManager: mainTab.taskManager,
                homeViewModel: mainTab.homeViewModel,
                aiSettingsViewModel: mainTab.aiSettingsViewModel,
                autoSmallTaskCoordinator: mainTab.chatAutoSmallTaskCoordinator,
                onClose: {
                    activeHomeFullScreenCover = nil
                }
            )
            .task(id: threadID) {
                await mainTab.chatListViewModel.selectAndPrepare(threadID: threadID)
                await mainTab.chatDetailViewModel.loadMessagesIfNeeded(
                    for: threadID,
                    lockBottomViewport: true
                )
            }
        }
    }

    private var healthResourceConversationCoordinator: HealthResourceConversationCoordinator {
        HealthResourceConversationCoordinator(
            stateStore: mainTab.chatStateStore,
            listViewModel: mainTab.chatListViewModel,
            detailViewModel: mainTab.chatDetailViewModel
        )
    }

    private func handleHealthResourceConversationRequest(
        _ request: HealthResourceConversationRequest
    ) {
        guard activeHomeFullScreenCover == nil,
              isPreparingHealthResourceConversation == false else { return }
        pendingHealthResourceConversationRequest = request
        Task { await preparePendingHealthResourceConversation() }
    }

    private func preparePendingHealthResourceConversation() async {
        guard let request = pendingHealthResourceConversationRequest,
              activeHomeFullScreenCover == nil,
              isPreparingHealthResourceConversation == false else { return }
        isPreparingHealthResourceConversation = true
        defer { isPreparingHealthResourceConversation = false }

        let result = await healthResourceConversationCoordinator.prepare(request)
        switch result {
        case .ready(let threadID):
            pendingHealthResourceConversationRequest = nil
            activeHomeFullScreenCover = .chat(threadID: threadID)
        case .requiresAISettings:
            showNoAvailableHealthChatModelAlert = true
        case .failed(let message):
            pendingHealthResourceConversationRequest = nil
            mainTab.chatDetailViewModel.notifyHealthResourceConversationError(message)
        }
    }

    @ViewBuilder
    func memberDetailFullScreenCover(memberID: Int) -> some View {
        CompatibleNavigationContainer {
            MemberDetailView(
                memberID: memberID,
                bindingUseCase: mainTab.homeDependencies.manageMemberBindingUseCase,
                moduleSetupUseCase: mainTab.homeDependencies.memberModuleSetupUseCase,
                nutritionGoalUseCase: mainTab.homeDependencies.nutritionDependencies.goalUseCase,
                nutritionDashboardUseCase: mainTab.homeDependencies.nutritionDependencies.dashboardUseCase,
                homeDependencies: mainTab.homeDependencies,
                memberContextStore: mainTab.homeViewModel.memberContextStoreForBinding,
                memberAPI: mainTab.homeDependencies.medicalMemberAPI,
                shareUseCase: mainTab.homeDependencies.shareMemberUseCase,
                onClose: {
                    activeHomeFullScreenCover = nil
                },
                onEdit: {
                    if let member = mainTab.homeViewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                        mainTab.homeViewModel.activeSheet = .addMember(.edit(member))
                    }
                },
                onDeleted: {
                    activeHomeFullScreenCover = nil
                    Task { await mainTab.homeViewModel.refresh() }
                }
            )
        }
    }
}
