import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// iOS 26 首页独立 root：承载工作台、sheet/cover、Launch Intent 与上传/成员详情等宿主能力。
@available(iOS 26.0, *)
struct IOS26HomeView: View {
    let dependencies: HomeFeatureDependencies
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator
    let session: UserSession
    let actionHandler: IOS26HomeDashboardActionHandler
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel

    @State private var hasLoaded = false
    @State private var activeFullScreenCover: HomeFullScreenCover?
    @State private var showExternalImportErrorAlert = false
    @State private var addMemberNearbyTransport = NearbyShareTransport()

    private var launchIntentConsumer: HomeLaunchIntentConsumer {
        dependencies.homeLaunchIntentConsumer
    }

    var body: some View {
        content
    }
}

@available(iOS 26.0, *)
private extension IOS26HomeView {
    var dashboardContent: some View {
        IOS26HomeDashboardView(
            viewModel: viewModel,
            taskManager: taskManager,
            session: session,
            actionHandler: actionHandler,
            chatListViewModel: chatListViewModel,
            deepTutorChatViewModel: deepTutorChatViewModel
        )
        .refreshable {
            await viewModel.refresh()
            await taskManager.syncIncremental(memberID: viewModel.selectedMemberID)
        }
        .navigationBarHidden(true)
    }

    var contentWithPresentation: some View {
        dashboardContent
            .sheet(item: $viewModel.activeSheet) { sheet in
                homeSheetContent(sheet)
            }
            .fullScreenCover(item: $activeFullScreenCover) { cover in
                homeFullScreenCoverContent(cover)
            }
    }

    var contentWithLifecycle: some View {
        contentWithPresentation
            .onAppear {
                launchIntentConsumer.setHomeHostReady(true)
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "ios26_home_appear")
            }
            .onDisappear {
                launchIntentConsumer.setHomeHostReady(false)
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                viewModel.consumePendingShareTicketIfNeeded()
                viewModel.consumePendingInviteIfNeeded()
                await viewModel.loadInitialIfNeeded(syncRemote: true)
                requestLaunchIntentDrain(reason: "ios26_home_initial_load")
            }
            .task(id: launchIntentCoordinator.queueRevision) {
                requestLaunchIntentDrain(reason: "queue_revision")
            }
            .onChange(of: launchIntentCoordinator.readiness.canConsume) { _, canConsume in
                guard canConsume else { return }
                requestLaunchIntentDrain(reason: "readiness_ready")
            }
            .onChange(of: viewModel.activeSheet?.id) { _, _ in
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "home_sheet_changed")
            }
            .onChange(of: viewModel.pendingMemberDetailMemberID) { _, memberID in
                guard let memberID else { return }
                activeFullScreenCover = .memberDetail(memberID: memberID)
                viewModel.pendingMemberDetailMemberID = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .medicationReminderPreferencesChanged)) { _ in
                triggerMedicationReminderRebuildIfSignedIn(reason: "preferences_changed")
            }
    }

    var content: some View {
        contentWithLifecycle
            .onChange(of: activeFullScreenCover) { _, cover in
                if cover != .medicalDocumentUpload, medicalDocumentUploadViewModel.isUploadPresented {
                    medicalDocumentUploadViewModel.dismissUploadPage()
                }
                syncLaunchIntentHostState()
                if cover == nil {
                    requestLaunchIntentDrain(reason: "cover_dismissed")
                }
            }
            .onChange(of: medicalDocumentUploadViewModel.isUploadPresented) { _, isPresented in
                if isPresented {
                    activeFullScreenCover = .medicalDocumentUpload
                } else if activeFullScreenCover == .medicalDocumentUpload {
                    activeFullScreenCover = nil
                }
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "upload_presented_changed")
            }
            .onChange(of: medicalDocumentUploadViewModel.stage) { _, _ in
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "upload_stage_changed")
            }
            .onChange(of: externalMedicalDocumentImportCoordinator.errorMessage) { _, message in
                showExternalImportErrorAlert = message != nil
            }
            .alert("无法导入文档", isPresented: $showExternalImportErrorAlert) {
                Button("好", role: .cancel) {
                    externalMedicalDocumentImportCoordinator.clearError()
                }
            } message: {
                Text(externalMedicalDocumentImportCoordinator.errorMessage ?? "")
            }
            .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _, _ in
                Task {
                    await viewModel.refresh()
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedMemberID)
    }

    func syncLaunchIntentHostState() {
        launchIntentConsumer.syncHostState(
            activeSheet: viewModel.activeSheet,
            activeFullScreenCover: activeFullScreenCover,
            isUploadPresented: medicalDocumentUploadViewModel.isUploadPresented,
            uploadStage: medicalDocumentUploadViewModel.stage
        )
    }

    func requestLaunchIntentDrain(reason: String) {
        launchIntentConsumer.requestDrain(reason: reason) { activeFullScreenCover = $0 }
    }

    func triggerMedicationReminderRebuildIfSignedIn(reason: String) {
        dependencies.medicationReminderSyncCoordinator.activate(accountID: session.accountID)
        dependencies.medicationReminderSyncCoordinator.requestRebuild(
            accountID: session.accountID,
            members: viewModel.dashboard?.members ?? dependencies.memberContextStore.context.members,
            reason: reason,
            immediate: true
        )
    }
}

@available(iOS 26.0, *)
private extension IOS26HomeView {
    @ViewBuilder
    func homeSheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .addMember(let addMemberSheet):
            CompatibleNavigationContainer {
                switch addMemberSheet {
                case .create(let pendingTicket):
                    AddFamilyMemberView(
                        mode: .create,
                        store: viewModel.memberContextStoreForBinding,
                        shareUseCase: dependencies.shareMemberUseCase,
                        inviteUseCase: dependencies.memberInviteUseCase,
                        nearbyTransport: addMemberNearbyTransport,
                        initialPendingTicket: pendingTicket,
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        },
                        onCreatedMemberCompleted: { member in
                            viewModel.selectMember(member.id)
                        },
                        homeDependencies: dependencies
                    )
                case .edit(let member):
                    AddFamilyMemberView(mode: .edit(member), store: viewModel.memberContextStoreForBinding)
                case .acceptInvite(let inviteID, let preview):
                    AddFamilyMemberView(
                        mode: .acceptInvite(inviteID: inviteID, preview: preview),
                        store: viewModel.memberContextStoreForBinding,
                        inviteUseCase: dependencies.memberInviteUseCase,
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        }
                    )
                }
            }

        case .pendingInvites:
            PendingMemberInvitesView(viewModel: viewModel)

        case .memberModuleSetup(let member):
            MemberSetupFlowView(
                mode: .maintain(member),
                store: viewModel.memberContextStoreForBinding,
                homeDependencies: dependencies,
                onMemberCreated: { member in
                    viewModel.selectMember(member.id)
                    Task { await viewModel.refresh() }
                }
            )

        case .share(let member):
            ShareSheet(
                member: member,
                shareUseCase: dependencies.shareMemberUseCase,
                inviteUseCase: dependencies.memberInviteUseCase
            )

        case .taskCenter:
            CompatibleNavigationContainer {
                TaskCenterViewController(
                    memberID: viewModel.selectedMemberID,
                    taskManager: taskManager
                )
            }
        }
    }

    @ViewBuilder
    func homeFullScreenCoverContent(_ cover: HomeFullScreenCover) -> some View {
        switch cover {
        case .medicalDocumentUpload:
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: dependencies.aiSettingsViewModel
                )
            }

        case .customCamera:
            CustomCameraHomeView {
                activeFullScreenCover = nil
            }

        case .memberDetail(let memberID):
            memberDetailFullScreenCover(memberID: memberID)
        }
    }

    @ViewBuilder
    func memberDetailFullScreenCover(memberID: Int) -> some View {
        CompatibleNavigationContainer {
            MemberDetailView(
                memberID: memberID,
                bindingUseCase: dependencies.manageMemberBindingUseCase,
                moduleSetupUseCase: dependencies.memberModuleSetupUseCase,
                nutritionGoalUseCase: dependencies.nutritionDependencies.goalUseCase,
                nutritionDashboardUseCase: dependencies.nutritionDependencies.dashboardUseCase,
                homeDependencies: dependencies,
                memberContextStore: viewModel.memberContextStoreForBinding,
                memberAPI: dependencies.medicalMemberAPI,
                shareUseCase: dependencies.shareMemberUseCase,
                onClose: {
                    activeFullScreenCover = nil
                },
                onEdit: {
                    if let member = viewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                        viewModel.activeSheet = .addMember(.edit(member))
                    }
                },
                onDeleted: {
                    activeFullScreenCover = nil
                    Task { await viewModel.refresh() }
                }
            )
        }
    }
}
