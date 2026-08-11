import Foundation

/// 领域装配器：每个 Assembly 只暴露本领域 facade，避免 AppContainer 继续向 UI 泄露完整系统地图。
protocol FeatureAssembly {
    associatedtype Facade
    var scope: DependencyScope { get }
    func makeFacade() -> Facade
}

struct AuthFeatureDependencies {
    let sessionStore: AppSessionStore
    let makeLoginViewModel: @MainActor () -> LoginViewModel
}

struct AIConfigFacade {
    let configCenter: AIConfigCenter
    let runtimeStore: AIRuntimeStore
    let makeSettingsViewModel: @MainActor (_ ownerAccountID: Int64) -> AISettingsViewModel
}

struct ChatFeatureDependencies {
    let stateStore: ChatStateStore
    let listViewModel: ChatListViewModel
    let detailViewModel: ChatDetailViewModel
    let syncSupervisor: ChatSyncSupervisor
}

struct MedicalFeatureDependencies {
    let memberContextStore: MemberContextStore
    let medicalSyncService: MedicalSyncService
    let makeUploadViewModel: @MainActor () -> MedicalDocumentUploadViewModel
}

struct HomeFeatureDependencies {
    let medicalWorkflowAPI: SparkMedicalWorkflowAPI
    let medicalQueryAPI: SparkMedicalQueryAPI
    let medicalMemberAPI: SparkMedicalMemberAPI
    let memberModuleSetupUseCase: MemberModuleSetupUseCase
    let shareMemberUseCase: ShareMemberUseCase
    let memberInviteUseCase: MemberInviteUseCase
    let manageMemberBindingUseCase: ManageMemberBindingUseCase
    let fileTransferService: FileTransferService
    let taskManager: TaskManager
    let logger: Logger
    let memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    /// 成员引导、成员详情等嵌套流程专用上传 VM，与首页 Tab 级单例隔离，避免 `isUploadPresented` 联动首页全屏层。
    let memberFlowMedicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let aiSettingsViewModel: AISettingsViewModel
    let routeStore: AppRouteStore
    let sessionStore: AppSessionStore
    let medicationReminderSyncCoordinator: MedicationReminderSyncCoordinator
    let medicationReminderOwnershipCoordinator: MedicationReminderOwnershipCoordinator
    let nutritionDependencies: NutritionFeatureDependencies
    let launchIntentCoordinator: LaunchIntentCoordinator
    let homeLaunchIntentConsumer: HomeLaunchIntentConsumer
}

struct KnowledgeFeatureDependencies {
    let makeEditorViewModel: @MainActor (_ documentID: UUID) -> KnowledgeDocumentEditorViewModel
}

struct PopularScienceFeatureDependencies {
    let makeDetailViewModel: @MainActor (_ articleID: Int) -> PopularScienceArticleDetailViewModel
}

extension HomeFeatureDependencies {
    @MainActor
    static func makeNutritionDependencies(
        backend: Backend,
        memberContextStore: MemberContextStore,
        aiRuntimeService: AIRuntimeService,
        configCenter: AIConfigCenter,
        notificationStore: NotificationStore,
        logger: Logger
    ) -> NutritionFeatureDependencies {
        let repository = NutritionRepository(api: backend.nutrition)
        let promptFactory = NutritionPromptFactory()
        let imageDescriber = NutritionFoodImageDescriber(
            runtimeService: aiRuntimeService,
            configCenter: configCenter,
            promptFactory: promptFactory,
            logger: logger
        )
        let intakeExtractor = NutritionIntakeStructuredExtractor(
            runtimeService: aiRuntimeService,
            configCenter: configCenter,
            promptFactory: promptFactory,
            jsonNormalizer: MedicalDocumentModelJSONNormalizer(),
            logger: logger
        )
        let recognitionPipeline = DefaultNutritionRecognitionPipeline(
            imageDescriber: imageDescriber,
            intakeExtractor: intakeExtractor,
            logger: logger
        )
        let healthKitStore = NutritionHealthKitStore(logger: logger)
        return NutritionFeatureDependencies(
            dashboardUseCase: NutritionDashboardUseCase(repository: repository, logger: logger),
            mealRecordUseCase: NutritionMealRecordUseCase(repository: repository, logger: logger),
            searchUseCase: NutritionSearchUseCase(repository: repository, logger: logger),
            healthKitSyncUseCase: NutritionHealthKitSyncUseCase(
                repository: repository,
                healthKitStore: healthKitStore,
                logger: logger
            ),
            energyBurnUseCase: NutritionEnergyBurnUseCase(repository: repository, logger: logger),
            goalUseCase: NutritionGoalUseCase(repository: repository, logger: logger),
            recognitionPipeline: recognitionPipeline,
            configCenter: configCenter,
            memberContextStore: memberContextStore,
            notificationStore: notificationStore,
            logger: logger
        )
    }

    @MainActor
    static var preview: HomeFeatureDependencies {
        let container = AppContainer.preview
        let routeStore = AppRouteStore()
        let uploadViewModel = container.makeMedicalDocumentUploadViewModel()
        let memberFlowUploadViewModel = container.makeScopedMedicalDocumentUploadViewModel()
        let homeViewModel = container.makeHomeViewModel()
        let homeLaunchIntentConsumer = HomeLaunchIntentConsumer(
            coordinator: container.launchIntentCoordinator,
            routeStore: routeStore,
            uploadViewModel: uploadViewModel,
            homeViewModel: homeViewModel,
            sessionStore: container.sessionStore,
            logger: container.logger
        )
        let ownershipCoordinator = MedicationReminderOwnershipCoordinator(
            medicalQueryAPI: container.backend.medicalQuery,
            syncCoordinator: container.medicationReminderSyncCoordinator,
            notificationClient: container.notificationClient,
            logger: container.logger
        )
        return HomeFeatureDependencies(
            medicalWorkflowAPI: container.backend.medicalWorkflow,
            medicalQueryAPI: container.backend.medicalQuery,
            medicalMemberAPI: container.backend.medicalMembers,
            memberModuleSetupUseCase: MemberModuleSetupUseCase(
                medicalQueryAPI: container.backend.medicalQuery,
                logger: container.logger
            ),
            shareMemberUseCase: ShareMemberUseCase(memberAPI: container.backend.medicalMembers),
            memberInviteUseCase: MemberInviteUseCase(memberAPI: container.backend.medicalMembers),
            manageMemberBindingUseCase: ManageMemberBindingUseCase(memberAPI: container.backend.medicalMembers),
            fileTransferService: container.fileTransferService,
            taskManager: container.taskManager,
            logger: container.logger,
            memberContextStore: container.memberContextStore,
            notificationClient: container.notificationClient,
            medicalDocumentUploadViewModel: uploadViewModel,
            memberFlowMedicalDocumentUploadViewModel: memberFlowUploadViewModel,
            aiSettingsViewModel: container.makeAISettingsViewModel(ownerAccountID: 1),
            routeStore: routeStore,
            sessionStore: container.sessionStore,
            medicationReminderSyncCoordinator: container.medicationReminderSyncCoordinator,
            medicationReminderOwnershipCoordinator: ownershipCoordinator,
            nutritionDependencies: makeNutritionDependencies(
                backend: container.backend,
                memberContextStore: container.memberContextStore,
                aiRuntimeService: container.aiRuntimeService,
                configCenter: container.aiConfigCenter,
                notificationStore: container.notificationStore,
                logger: container.logger
            ),
            launchIntentCoordinator: container.launchIntentCoordinator,
            homeLaunchIntentConsumer: homeLaunchIntentConsumer
        )
    }
}

extension KnowledgeFeatureDependencies {
    @MainActor
    static var preview: KnowledgeFeatureDependencies {
        let container = AppContainer.preview
        return KnowledgeFeatureDependencies(
            makeEditorViewModel: { documentID in
                container.makeKnowledgeDocumentEditorViewModel(documentID: documentID)
            }
        )
    }
}

struct NotificationFeatureDependencies {
    let store: NotificationStore
    let client: any NotificationClient
    let pushAdapter: PushAdapter
}

struct OnboardingFeatureDependencies {
    let store: OnboardingStore
    let makeFlowViewModel: @MainActor () -> OnboardingFlowViewModel
}

/// 主 Tab 运行所需的稳定依赖包。
///
/// 这组对象属于账号级 UI 运行时：同一账号登录期间只初始化一次，网络状态、前后台切换、
/// SwiftUI body 重算都不能导致它们重新创建或清空缓存。
struct MainTabDependencies {
    let scope: DependencyScope
    let routeStore: AppRouteStore
    let homeDependencies: HomeFeatureDependencies
    let knowledgeDependencies: KnowledgeFeatureDependencies
    let popularScienceDependencies: PopularScienceFeatureDependencies
    let taskManager: TaskManager
    let homeViewModel: HomeViewModel
    let medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let knowledgeViewModel: KnowledgeLibraryViewModel
    let popularScienceViewModel: PopularScienceHomeViewModel
    let chatStateStore: ChatStateStore
    let chatListViewModel: ChatListViewModel
    let chatDetailViewModel: ChatDetailViewModel
    let chatAutoSmallTaskIntentStore: ChatAutoSmallTaskIntentStore
    let chatAutoSmallTaskCoordinator: ChatAutoSmallTaskCoordinator
    let autoSmallTaskRegistry: AutoSmallTaskRegistry
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let settingsViewModel: SettingsViewModel
    let accountManagementViewModel: AccountManagementViewModel
    let aiSettingsViewModel: AISettingsViewModel
    let versionUpdateCoordinator: AppVersionUpdateCoordinator
    let upgradeLoginViewModel: LoginViewModel
    let memberContextStore: MemberContextStore
    let pushAdapter: PushAdapter
    let externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    let launchIntentCoordinator: LaunchIntentCoordinator
}

struct MainTabFeatureDependencies {
    let makeDependencies: @MainActor (_ ownerAccountID: Int64) -> MainTabDependencies
}

struct AppFeatureFacades {
    let auth: AuthFeatureDependencies
    let ai: AIConfigFacade
    let chat: ChatFeatureDependencies
    let medical: MedicalFeatureDependencies
    let notifications: NotificationFeatureDependencies
    let onboarding: OnboardingFeatureDependencies
    let mainTab: MainTabFeatureDependencies
}

/// App 根视图需要的依赖包。UI 层只消费这个包，不再持有完整 AppContainer。
struct AppContentDependencies {
    let notificationStore: NotificationStore
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let routeCoordinator: RouteCoordinator
    let versionUpdateCoordinator: AppVersionUpdateCoordinator
    let externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    let coordinator: AppCoordinatorDependencies
}

/// AppCoordinatorView 只需要 facade 和生命周期协调器。
struct AppCoordinatorDependencies {
    let facades: AppFeatureFacades
    let lifecycle: AppLifecycleCoordinator
    let versionUpdateCoordinator: AppVersionUpdateCoordinator
}

struct AppAssembly: FeatureAssembly {
    let auth: AuthAssembly
    let ai: AIAssembly
    let chat: ChatAssembly
    let medical: MedicalAssembly
    let notifications: NotificationAssembly
    let onboarding: OnboardingAssembly
    let mainTab: MainTabAssembly
    let logger: Logger
    let scope: DependencyScope = .appSingleton

    func makeFacade() -> AppFeatureFacades {
        logger.info("AppAssembly 开始组装领域 facade", module: .general)
        return AppFeatureFacades(
            auth: auth.makeFacade(),
            ai: ai.makeFacade(),
            chat: chat.makeFacade(),
            medical: medical.makeFacade(),
            notifications: notifications.makeFacade(),
            onboarding: onboarding.makeFacade(),
            mainTab: mainTab.makeFacade()
        )
    }
}

struct AuthAssembly: FeatureAssembly {
    let sessionStore: AppSessionStore
    let makeLoginViewModel: @MainActor () -> LoginViewModel
    let logger: Logger
    let scope: DependencyScope = .appSingleton

    func makeFacade() -> AuthFeatureDependencies {
        logger.debug("AuthAssembly 输出认证 facade", module: .auth)
        return AuthFeatureDependencies(
            sessionStore: sessionStore,
            makeLoginViewModel: makeLoginViewModel
        )
    }
}

struct AIAssembly: FeatureAssembly {
    let configCenter: AIConfigCenter
    let runtimeStore: AIRuntimeStore
    let makeSettingsViewModel: @MainActor (_ ownerAccountID: Int64) -> AISettingsViewModel
    let logger: Logger
    let scope: DependencyScope = .accountScoped

    func makeFacade() -> AIConfigFacade {
        logger.debug("AIAssembly 输出 AI 配置 facade", module: .aiConfig)
        return AIConfigFacade(
            configCenter: configCenter,
            runtimeStore: runtimeStore,
            makeSettingsViewModel: makeSettingsViewModel
        )
    }
}

struct ChatAssembly: FeatureAssembly {
    let stateStore: ChatStateStore
    let listViewModel: ChatListViewModel
    let detailViewModel: ChatDetailViewModel
    let syncSupervisor: ChatSyncSupervisor
    let logger: Logger
    let scope: DependencyScope = .accountScoped

    func makeFacade() -> ChatFeatureDependencies {
        logger.debug("ChatAssembly 输出聊天 facade", module: .general)
        return ChatFeatureDependencies(
            stateStore: stateStore,
            listViewModel: listViewModel,
            detailViewModel: detailViewModel,
            syncSupervisor: syncSupervisor
        )
    }
}

struct MedicalAssembly: FeatureAssembly {
    let memberContextStore: MemberContextStore
    let medicalSyncService: MedicalSyncService
    let makeUploadViewModel: @MainActor () -> MedicalDocumentUploadViewModel
    let logger: Logger
    let scope: DependencyScope = .accountScoped

    func makeFacade() -> MedicalFeatureDependencies {
        logger.debug("MedicalAssembly 输出医疗 facade", module: .medical)
        return MedicalFeatureDependencies(
            memberContextStore: memberContextStore,
            medicalSyncService: medicalSyncService,
            makeUploadViewModel: makeUploadViewModel
        )
    }
}

struct NotificationAssembly: FeatureAssembly {
    let store: NotificationStore
    let client: any NotificationClient
    let pushAdapter: PushAdapter
    let logger: Logger
    let scope: DependencyScope = .appSingleton

    func makeFacade() -> NotificationFeatureDependencies {
        logger.debug("NotificationAssembly 输出通知 facade", module: .push)
        return NotificationFeatureDependencies(
            store: store,
            client: client,
            pushAdapter: pushAdapter
        )
    }
}

struct OnboardingAssembly: FeatureAssembly {
    let store: OnboardingStore
    let makeFlowViewModel: @MainActor () -> OnboardingFlowViewModel
    let logger: Logger
    let scope: DependencyScope = .accountScoped

    func makeFacade() -> OnboardingFeatureDependencies {
        logger.debug("OnboardingAssembly 输出引导流程 facade", module: .general)
        return OnboardingFeatureDependencies(
            store: store,
            makeFlowViewModel: makeFlowViewModel
        )
    }
}

struct MainTabAssembly: FeatureAssembly {
    let makeDependencies: @MainActor (_ ownerAccountID: Int64) -> MainTabDependencies
    let logger: Logger
    let scope: DependencyScope = .accountScoped

    func makeFacade() -> MainTabFeatureDependencies {
        logger.debug("MainTabAssembly 输出主 Tab facade", module: .general)
        return MainTabFeatureDependencies(
            makeDependencies: makeDependencies
        )
    }
}
