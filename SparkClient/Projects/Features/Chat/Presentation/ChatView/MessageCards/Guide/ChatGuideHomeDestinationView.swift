import SwiftUI
import UIKit

/// 引导卡片滑块点击后跳转的独立模块页面（CHAT-000025 v2：不再跳 IOS26 汇总页）。
enum ChatGuideHomeModule {
    /// 运动健康模块（FitnessHomeView）
    case fitness
    /// 饮食营养模块（NutritionHomeView）
    case nutrition
    /// 经典健康首页（HealthHomeView：成员健康总览 + 医疗档案）
    case healthHome
}

/// 引导卡片滑块类别 → 独立模块页映射：
/// - 运动 → 运动健康模块
/// - 饮食 → 饮食营养模块
/// - 身材/医疗 → 经典健康首页（成员健康总览 / 医疗档案区域）
extension ChatGuideMetricCategory {
    var guideHomeModule: ChatGuideHomeModule {
        switch self {
        case .movement:
            return .fitness
        case .bodyManagement:
            return .healthHome
        case .nutrition:
            return .nutrition
        case .medical:
            return .healthHome
        }
    }
}

/// 对话引导卡片滑块 push 出来的模块首页 destination（CHAT-000025）：
/// 按滑块类别直接进入对应模块独立页面，不经过 IOS26 汇总首页、不切主 Tab：
/// - 运动 → `FitnessHomeView`（自带导航栏与工具栏）
/// - 饮食 → `NutritionHomeView`（自带导航栏与工具栏）
/// - 身材/医疗 → `HealthHomeView`（经典健康首页，本视图补齐头部 toolbar）
/// 由 App 宿主（IOS26TabBarView / MainTabCoordinatorView）构造，Chat 侧仅通过
/// `ChatGuideHomeDestinationBuilder` 闭包拿到 `AnyView`，不感知首页依赖细节。
struct ChatGuideHomeDestinationView: View {
    let category: ChatGuideMetricCategory

    let dependencies: HomeFeatureDependencies
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator
    let session: UserSession
    @ObservedObject var chatListViewModel: ChatListViewModel
    let autoSmallTaskRegistry: AutoSmallTaskRegistry
    let autoSmallTaskIntentStore: ChatAutoSmallTaskIntentStore
    @Binding var activeFullScreenCover: HomeFullScreenCover?

    // toolbar 右侧入口所需的宿主依赖（与主 Tab 各分支一致）
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject var upgradeLoginViewModel: LoginViewModel

    @State private var showsDeviceAccountUpgradeSheet = false

    init(
        category: ChatGuideMetricCategory,
        dependencies: HomeFeatureDependencies,
        homeViewModel: HomeViewModel,
        taskManager: TaskManager,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator,
        launchIntentCoordinator: LaunchIntentCoordinator,
        session: UserSession,
        chatListViewModel: ChatListViewModel,
        autoSmallTaskRegistry: AutoSmallTaskRegistry,
        autoSmallTaskIntentStore: ChatAutoSmallTaskIntentStore,
        activeFullScreenCover: Binding<HomeFullScreenCover?>,
        settingsViewModel: SettingsViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        accountManagementViewModel: AccountManagementViewModel,
        versionUpdateCoordinator: AppVersionUpdateCoordinator,
        upgradeLoginViewModel: LoginViewModel
    ) {
        self.category = category
        self.dependencies = dependencies
        self.homeViewModel = homeViewModel
        self.taskManager = taskManager
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.externalMedicalDocumentImportCoordinator = externalMedicalDocumentImportCoordinator
        self.launchIntentCoordinator = launchIntentCoordinator
        self.session = session
        self.chatListViewModel = chatListViewModel
        self.autoSmallTaskRegistry = autoSmallTaskRegistry
        self.autoSmallTaskIntentStore = autoSmallTaskIntentStore
        self._activeFullScreenCover = activeFullScreenCover
        self.settingsViewModel = settingsViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.accountManagementViewModel = accountManagementViewModel
        self.versionUpdateCoordinator = versionUpdateCoordinator
        self.upgradeLoginViewModel = upgradeLoginViewModel
    }

    var body: some View {
//        IOS26HomeView(
//                   dependencies: dependencies,
//                   viewModel: homeViewModel,
//                   taskManager: taskManager,
//                   medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
//                   externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
//                   launchIntentCoordinator: launchIntentCoordinator,
//                   session: session,
//                   actionHandler: actionHandler,
//                   chatListViewModel: chatListViewModel,
//                   currentSection: $currentSection,
//                   safeAreaRefreshRevision: safeAreaRefreshRevision,
//                   activeFullScreenCover: $activeFullScreenCover
//               )
//               .navigationBarTitleDisplayMode(.inline)
//               .toolbar {
//                   ToolbarItem(placement: .topBarLeading) {
//                       memberSelectorHeader
//                   }
//                   healthHomeTrailingToolbar
//               }
//               .toolbar(.hidden, for: .tabBar)
//               .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
//                   LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
//               }
        modulePage
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
                LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
            }
    }

    // MARK: - 模块页面分发

    @ViewBuilder
    private var modulePage: some View {
        switch category.guideHomeModule {
        case .fitness:
            // 运动健康模块：独立成页，使用自带导航栏与工具栏
            FitnessHomeView(dependencies: dependencies.fitnessDependencies)

        case .nutrition:
            // 饮食营养模块：独立成页，使用自带导航栏与工具栏
            NutritionHomeView(dependencies: dependencies.nutritionDependencies)

        case .healthHome:
            // 经典健康首页（成员健康总览 + 医疗档案）：补齐头部 toolbar
            HealthHomeView(
                dependencies: dependencies,
                viewModel: homeViewModel,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: launchIntentCoordinator,
                session: session,
                taskManager: taskManager,
                chatListViewModel: chatListViewModel,
                autoSmallTaskRegistry: autoSmallTaskRegistry,
                autoSmallTaskIntentStore: autoSmallTaskIntentStore,
                activeFullScreenCover: $activeFullScreenCover
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    
//                }
                ToolbarItem(placement: .topBarTrailing) {
                    memberSelectorHeader
                }
            }
        }
    }

    // MARK: - 健康首页头部 toolbar

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

    private var settingsEntry: some View {
        MainNavigationLink {
            SettingsView(
                viewModel: settingsViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                accountManagementViewModel: accountManagementViewModel,
                versionUpdateCoordinator: versionUpdateCoordinator,
                memberContextStore: dependencies.memberContextStore,
                session: session,
                showsDeviceAccountUpgradeSheet: $showsDeviceAccountUpgradeSheet
            )
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel(L10n.text("settings.title"))
    }
}
