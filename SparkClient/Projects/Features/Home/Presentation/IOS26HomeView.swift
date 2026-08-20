import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// iOS 26 首页独立 root：承载工作台、Launch Intent 与上传/成员详情等宿主触发能力。
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
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator

    @State private var hasLoaded = false
    @Binding var showsDeviceAccountUpgradeSheet: Bool
    @Binding var activeFullScreenCover: HomeFullScreenCover?
    @State private var showExternalImportErrorAlert = false

    private var launchIntentConsumer: HomeLaunchIntentConsumer {
        dependencies.homeLaunchIntentConsumer
    }

    var body: some View {
        content
    }
}

@available(iOS 26.0, *)
private extension IOS26HomeView {
    var selectedMember: Member? {
        let members = viewModel.dashboard?.members ?? viewModel.memberContextStoreForBinding.context.members
        guard let selectedMemberID = viewModel.selectedMemberID else {
            return members.first
        }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }

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
        .navigationTitle(L10n.text("ios26.home.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                memberToolbarMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                MainNavigationLink {
                    SettingsView(
                        viewModel: settingsViewModel,
                        aiSettingsViewModel: aiSettingsViewModel,
                        accountManagementViewModel: accountManagementViewModel,
                        versionUpdateCoordinator: versionUpdateCoordinator,
                        memberContextStore: viewModel.memberContextStoreForBinding,
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

    @ViewBuilder
    var memberToolbarMenu: some View {
        if let selectedMember,
           viewModel.memberContextStoreForBinding.context.members.isEmpty == false {
            MemberProfileBindingMenu(
                memberContextStore: viewModel.memberContextStoreForBinding,
                selectedMemberID: viewModel.selectedMemberID,
                onSelect: { memberID in
                    guard let memberID, memberID != viewModel.selectedMemberID else { return }
                    viewModel.selectMember(memberID)
                    triggerHaptic(style: .light)
                }
            ) {
                MemberSelectorChip(
                    member: selectedMember,
                    badgeText: MemberSelectorChip.badgeText(for: selectedMember),
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
                    selectedMember.name
                )
            )
        }
    }

    var contentWithPresentation: some View {
        dashboardContent
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

    func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}
