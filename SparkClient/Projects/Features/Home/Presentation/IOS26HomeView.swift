import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// iOS 26 首页独立 root：承载工作台、Launch Intent 与上传/成员详情等宿主触发能力。
/// 顶部自定义分段头（参考 DreamHua MyHome.swift），支持左右滑动在新款首页、饮食营养、运动健康三个分页间切换。
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

    /// 首页内可左右切换的分页（参考 MyHome.Tab）。
    enum HomeSection: CaseIterable, Identifiable {
        case dashboard
        case nutrition
        case fitness

        var id: Self { self }

        /// 分段头标签
        var title: String {
            switch self {
            case .dashboard:
                return L10n.text("home.title")
            case .nutrition:
                return L10n.text("nutrition.home.title")
            case .fitness:
                return L10n.text("fitness.home.title")
            }
        }
    }

    @State private var hasLoaded = false
    @Binding var currentSection: HomeSection
    /// 标记切换来自点击分段头，屏蔽滑动偏移回调与切换动画的相互干扰（参考 MyHome.isTapped）。
    @State private var isSectionTapped = false
    /// 当前分页滑动偏移，驱动分段指示器实时跟随（参考 MyHome.offset）。
    @State private var sectionSwipeOffset: CGFloat = 0
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
    }

    // MARK: - 分段切换（参考 MyHome.swift DynamicTabHeader + TabView 分页）

    var contentWithPresentation: some View {
        GeometryReader { proxy in
            let size = proxy.size
            VStack(spacing: 0) {
                sectionHeader(size: size)
                sectionPager(size: size)
            }
        }
    }

    func sectionHeader(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                ForEach(HomeSection.allCases) { section in
                    Text(section.title)
                        .fontWeight(section == currentSection ? .black : .semibold)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard section != currentSection else { return }
                            // 点击切换时先屏蔽滑动偏移回调，避免与切换动画相互覆盖
                            isSectionTapped = true
                            withAnimation(.easeInOut) {
                                currentSection = section
                                sectionSwipeOffset = -(size.width) * CGFloat(indexOf(section: section))
                            }
                        }
                }
            }
            .overlay(alignment: .leading) {
                VStack {
                    Spacer()
                    Capsule()
                        .fill(.tint)
                        .frame(width: sectionIndicatorWidth(size: size), height: 4)
                        .offset(x: sectionIndicatorOffset(size: size))
                }
            }
        }
    }

    func sectionPager(size: CGSize) -> some View {
        TabView(selection: $currentSection) {
            dashboardContent
                .sectionOffsetTracker { value in
                    handleSectionSwipeOffset(value, section: .dashboard, size: size)
                }
                .tag(HomeSection.dashboard)

            NutritionHomeView(
                dependencies: dependencies.nutritionDependencies,
                showsNavigationChrome: false
            )
            .sectionOffsetTracker { value in
                handleSectionSwipeOffset(value, section: .nutrition, size: size)
            }
            .tag(HomeSection.nutrition)

            FitnessHomeView(
                dependencies: dependencies.fitnessDependencies,
                showsNavigationChrome: false
            )
            .sectionOffsetTracker { value in
                handleSectionSwipeOffset(value, section: .fitness, size: size)
            }
            .tag(HomeSection.fitness)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 用户快速滑动时提前解除点击态，恢复滑动跟踪（参考 MyHome.InteractionManager）
        .simultaneousGesture(
            DragGesture().onChanged { _ in
                isSectionTapped = false
            }
        )
    }

    func handleSectionSwipeOffset(_ value: CGFloat, section: HomeSection, size: CGSize) {
        guard size.width > 0 else { return }
        // 仅由当前分页驱动偏移，滑动过程中实时更新指示器位置
        if currentSection == section && !isSectionTapped && value != size.width {
            sectionSwipeOffset = value - (size.width * CGFloat(indexOf(section: section)))
        }
        // 点击切换的动画落定后恢复滑动跟踪
        if value == 0 && isSectionTapped {
            isSectionTapped = false
        }
    }

    // MARK: 分段指示器几何（参考 MyHome.tabOffset / indexOf）

    func sectionIndicatorWidth(size: CGSize) -> CGFloat {
        size.width / (CGFloat(HomeSection.allCases.count) * 3)
    }

    func sectionIndicatorOffset(size: CGSize) -> CGFloat {
        let slotWidth = size.width / CGFloat(HomeSection.allCases.count)
        return (-sectionSwipeOffset / size.width) * slotWidth + sectionIndicatorWidth(size: size)
    }

    func indexOf(section: HomeSection) -> Int {
        HomeSection.allCases.firstIndex { $0 == section } ?? 0
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

// MARK: - 分页滑动偏移追踪（参考 MyHome.offsetX + OffsetKey）

private struct HomeSectionOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    /// 回传视图在全局坐标系中的 minX，用于驱动分段指示器跟随分页滑动。
    func sectionOffsetTracker(onChange: @escaping (CGFloat) -> Void) -> some View {
        overlay {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HomeSectionOffsetKey.self, value: proxy.frame(in: .global).minX)
                    .onPreferenceChange(HomeSectionOffsetKey.self, perform: onChange)
            }
        }
    }
}
