import Foundation

/// 组合根容器：负责初始化基础设施并组装跨 Feature 的依赖关系。
@MainActor
final class AppContainer {
    let coreDataStack: CoreDataStack
    let backend: Backend
    let logger: Logger
    let fileCacheManager: FileCacheManager
    let fileTransferService: FileTransferService

    let routeStore: AppRouteStore
    let appBootstrapper: AppBootstrapper
    let notificationStore: NotificationStore
    let notificationMetricsStore: NotificationMetricsStore
    let notificationInboxStore: NotificationInboxStore
    let notificationQueue: NotificationQueue
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let publishNotificationUseCase: PublishNotificationUseCase
    let notificationClient: any NotificationClient
    let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    let pushAdapter: PushAdapter

    let userProfileRepository: any UserProfileRepository
    let healthMetricsRepository: any HealthMetricsRepository
    let authRepository: any AuthRepository
    let aiSettingsRepository: any AISettingsRepository

    let restoreSessionUseCase: RestoreSessionUseCase
    let signInWithAppleUseCase: SignInWithAppleUseCase
    let signOutUseCase: SignOutUseCase
    let loadHomeDashboardUseCase: LoadHomeDashboardUseCase
    let manageHomeMemberUseCase: ManageHomeMemberUseCase
    let requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase
    let loadHealthTimelineUseCase: LoadHealthTimelineUseCase
    let loadPatientsUseCase: LoadPatientsUseCase
    let selectPatientUseCase: SelectPatientUseCase
    let extractMedicalDraftFromDocumentUseCase: ExtractMedicalDraftFromDocumentUseCase
    let confirmMedicalDraftUseCase: ConfirmMedicalDraftUseCase
    let loadLatestMedicalDraftUseCase: LoadLatestMedicalDraftUseCase
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase
    let loadChatThreadUseCase: LoadChatThreadUseCase
    let createChatThreadUseCase: CreateChatThreadUseCase
    let sendChatMessageUseCase: SendChatMessageUseCase

    let aiRuntimeStore: AIRuntimeStore
    let aiConfigCenter: AIConfigCenter
    let aiRuntimeService: AIRuntimeService
    let toolHub: ToolHub
        let toolAuditStore: ToolAuditStore
        let medicalSyncService: MedicalSyncService
        let ocrOrchestrator: OCROrchestrator

    let sessionStore: AppSessionStore
    let patientContextStore: PatientContextStore

    init(
        coreDataStack: CoreDataStack,
        backend: Backend,
        ocrConfiguration: OCRConfiguration = OCRConfiguration(),
        logger: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.backend = backend
        self.logger = logger
        self.fileCacheManager = FileCacheManager(logger: logger)
        self.fileTransferService = FileTransferService(api: backend.files, cacheManager: fileCacheManager, logger: logger)

        // Repository 统一在这里装配，ViewModel 只依赖 UseCase。
        let profileRepository = CoreDataUserProfileRepository(coreDataStack: coreDataStack, logger: logger)
        let healthMetricsRepository = CoreDataHealthMetricsRepository(coreDataStack: coreDataStack, logger: logger)
        let authRepository = DefaultAuthRepository(
            backend: backend,
            userProfileRepository: profileRepository,
            healthMetricsRepository: healthMetricsRepository,
            logger: logger
        )
        let aiSettingsRepository = DefaultAISettingsRepository(logger: logger)
        let aiRuntimeStore = AIRuntimeStore()
        let remoteConfigProvider = BackendAIRemoteConfigProvider(api: backend.aiConfig)
        let medicalSyncPreferenceRepository = DefaultMedicalSyncPreferenceRepository()
        let healthMetricsSyncStore = HealthMetricsSyncStore(coreDataStack: coreDataStack, logger: logger)
        let coreDataMedicalSnapshotStore = CoreDataMedicalSnapshotStore(coreDataStack: coreDataStack)
        let medicalDataRepository = DefaultMedicalDataRepository(
            snapshotStore: coreDataMedicalSnapshotStore,
            healthMetricsStore: healthMetricsSyncStore,
            remoteAPI: backend.medicalSync,
            logger: logger
        )
        let homeMemberRepository = DefaultHomeMemberRepository(
            medicalDataRepository: medicalDataRepository,
            memberAPI: backend.medicalMembers,
            logger: logger
        )
        let homeHealthRepository = HealthKitHomeHealthDataRepository()
        let aiConfigCenter = AIConfigCenter(
            repository: aiSettingsRepository,
            remoteProvider: remoteConfigProvider,
            runtimeStore: aiRuntimeStore,
            logger: logger
        )
        let aliyunEngine: OCRTextEngine? = ocrConfiguration.enableAliyunOCR
            ? AliyunOCREngine(credentialsProvider: BackendOCRCredentialsProvider(api: backend.ocr))
            : nil
        let localServerEngine: OCRTextEngine? = ocrConfiguration.enableLocalServerOCR
            ? LocalServerOCREngine(
                baseURL: ocrConfiguration.localServerBaseURL,
                timeoutMs: ocrConfiguration.localServerTimeoutMs,
                authToken: ocrConfiguration.localServerAuthToken
            )
            : nil
        let ocrOrchestrator = OCROrchestrator(
            config: ocrConfiguration,
            aliyunEngine: aliyunEngine,
            localServerEngine: localServerEngine,
            logger: logger
        )
        let aiRuntimeGateway = OpenAICompatibleTextGateway(logger: logger)
        let aiRuntimeService = AIRuntimeService(
            configCenter: aiConfigCenter,
            gateway: aiRuntimeGateway,
            logger: logger
        )
        let patientRepository = DefaultPatientRepository(medicalDataRepository: medicalDataRepository)
        let medicalRecordRepository = DefaultMedicalRecordRepository(medicalDataRepository: medicalDataRepository)
        let draftRepository = InMemoryMedicalDraftRepository()
        let extractMedicalDraftFromDocumentUseCase = ExtractMedicalDraftFromDocumentUseCase(
            ocrOrchestrator: ocrOrchestrator,
            runtimeService: aiRuntimeService,
            draftRepository: draftRepository,
            logger: logger
        )
        let confirmMedicalDraftUseCase = ConfirmMedicalDraftUseCase(
            draftRepository: draftRepository,
            medicalDataRepository: medicalDataRepository
        )
        let loadLatestMedicalDraftUseCase = LoadLatestMedicalDraftUseCase(draftRepository: draftRepository)
        let toolAuditStore = ToolAuditStore()
        let toolHub = ToolHub(
            extractDraftUseCase: extractMedicalDraftFromDocumentUseCase,
            confirmDraftUseCase: confirmMedicalDraftUseCase,
            loadLatestDraftUseCase: loadLatestMedicalDraftUseCase,
            auditStore: toolAuditStore,
            logger: logger
        )
        let chatRepository = InMemoryChatRepository()
        let routeStore = AppRouteStore()
        let patientContextStore = PatientContextStore()
        let notificationStore = NotificationStore()
        let notificationMetricsStore = NotificationMetricsStore()
        let notificationInboxStore = NotificationInboxStore()
        let notificationQueue = NotificationQueue(
            metricsStore: notificationMetricsStore,
            inboxStore: notificationInboxStore,
            logger: logger
        )
        let notificationDeliveryCoordinator = NotificationDeliveryCoordinator(
            queue: notificationQueue,
            store: notificationStore,
            inboxStore: notificationInboxStore,
            metricsStore: notificationMetricsStore
        )
        let publishNotificationUseCase = PublishNotificationUseCase(
            queue: notificationQueue,
            deliveryCoordinator: notificationDeliveryCoordinator,
            logger: logger
        )
        let notificationClient = DefaultNotificationClient(
            publishUseCase: publishNotificationUseCase
        )
        let medicalSyncService = MedicalSyncService(
            preferenceRepository: medicalSyncPreferenceRepository,
            medicalRepository: medicalDataRepository,
            notificationClient: notificationClient,
            logger: logger
        )
        let handleRemoteNotificationUseCase = HandleRemoteNotificationUseCase(
            routeStore: routeStore,
            notificationClient: notificationClient
        )
        let pushAdapter = PushAdapter(
            handleRemoteNotificationUseCase: handleRemoteNotificationUseCase,
            logger: logger
        )
        let appBootstrapper = AppBootstrapper(
            aiConfigCenter: aiConfigCenter,
            medicalSyncService: medicalSyncService,
            routeStore: routeStore,
            logger: logger
        )

        self.userProfileRepository = profileRepository
        self.healthMetricsRepository = healthMetricsRepository
        self.authRepository = authRepository
        self.aiSettingsRepository = aiSettingsRepository

        self.restoreSessionUseCase = RestoreSessionUseCase(authRepository: authRepository)
        self.signInWithAppleUseCase = SignInWithAppleUseCase(authRepository: authRepository)
        self.signOutUseCase = SignOutUseCase(authRepository: authRepository)
        self.loadHomeDashboardUseCase = LoadHomeDashboardUseCase(
            userProfileRepository: profileRepository,
            memberRepository: homeMemberRepository,
            healthDataRepository: homeHealthRepository
        )
        self.manageHomeMemberUseCase = ManageHomeMemberUseCase(memberRepository: homeMemberRepository)
        self.requestHomeHealthAuthorizationUseCase = RequestHomeHealthAuthorizationUseCase(healthDataRepository: homeHealthRepository)
        self.loadHealthTimelineUseCase = LoadHealthTimelineUseCase(healthMetricsRepository: healthMetricsRepository)
        self.loadPatientsUseCase = LoadPatientsUseCase(repository: patientRepository)
        self.selectPatientUseCase = SelectPatientUseCase()
        self.extractMedicalDraftFromDocumentUseCase = extractMedicalDraftFromDocumentUseCase
        self.confirmMedicalDraftUseCase = confirmMedicalDraftUseCase
        self.loadLatestMedicalDraftUseCase = loadLatestMedicalDraftUseCase
        self.buildPatientContextSummaryUseCase = BuildPatientContextSummaryUseCase(repository: medicalRecordRepository)
        self.loadChatThreadUseCase = LoadChatThreadUseCase(repository: chatRepository)
        self.createChatThreadUseCase = CreateChatThreadUseCase(repository: chatRepository)
        self.sendChatMessageUseCase = SendChatMessageUseCase(
            repository: chatRepository,
            runtimeService: aiRuntimeService,
            buildPatientContextSummaryUseCase: buildPatientContextSummaryUseCase,
            toolHub: toolHub,
            consentGate: ConsentGate()
        )

        self.routeStore = routeStore
        self.aiRuntimeStore = aiRuntimeStore
        self.aiConfigCenter = aiConfigCenter
        self.aiRuntimeService = aiRuntimeService
        self.toolHub = toolHub
        self.toolAuditStore = toolAuditStore
        self.medicalSyncService = medicalSyncService
        self.ocrOrchestrator = ocrOrchestrator
        self.appBootstrapper = appBootstrapper
        self.notificationStore = notificationStore
        self.notificationMetricsStore = notificationMetricsStore
        self.notificationInboxStore = notificationInboxStore
        self.notificationQueue = notificationQueue
        self.notificationDeliveryCoordinator = notificationDeliveryCoordinator
        self.publishNotificationUseCase = publishNotificationUseCase
        self.notificationClient = notificationClient
        self.handleRemoteNotificationUseCase = handleRemoteNotificationUseCase
        self.pushAdapter = pushAdapter

        self.sessionStore = AppSessionStore(restoreSessionUseCase: restoreSessionUseCase)
        self.patientContextStore = patientContextStore
    }

    static func live() -> AppContainer {
        let environment = AppEnvironment.current
        SparkLogger.configure(level: environment.logLevel, subsystem: environment.subsystem)
        let logger = ConsoleLogger()
        let coreDataStack = CoreDataStack.shared
        let backend = Backend(baseURL: environment.apiBaseURL, logger: logger)
        return AppContainer(
            coreDataStack: coreDataStack,
            backend: backend,
            ocrConfiguration: environment.ocrConfiguration,
            logger: logger
        )
    }

    static let preview: AppContainer = {
        SparkLogger.configure(level: .debug, subsystem: "SparkClient.Preview")
        let logger = ConsoleLogger()
        let coreDataStack = CoreDataStack.preview
        let backend = Backend(baseURL: URL(string: "https://preview.sparkclient.local")!, logger: logger)
        return AppContainer(
            coreDataStack: coreDataStack,
            backend: backend,
            ocrConfiguration: OCRConfiguration(enableLocalServerOCR: false),
            logger: logger
        )
    }()

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(
            signInWithAppleUseCase: signInWithAppleUseCase,
            sessionStore: sessionStore
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            sessionStore: sessionStore,
            loadHomeDashboardUseCase: loadHomeDashboardUseCase,
            manageHomeMemberUseCase: manageHomeMemberUseCase,
            requestHomeHealthAuthorizationUseCase: requestHomeHealthAuthorizationUseCase,
            patientContextStore: patientContextStore,
            notificationClient: notificationClient
        )
    }

    func makeMedicalUploadFlowViewModel() -> MedicalUploadFlowViewModel {
        MedicalUploadFlowViewModel(
            patientContextStore: patientContextStore,
            extractMedicalDraftFromDocumentUseCase: extractMedicalDraftFromDocumentUseCase,
            confirmMedicalDraftUseCase: confirmMedicalDraftUseCase,
            logger: logger
        )
    }

    func makeHealthTimelineViewModel() -> HealthTimelineViewModel {
        HealthTimelineViewModel(
            sessionStore: sessionStore,
            loadHealthTimelineUseCase: loadHealthTimelineUseCase
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            sessionStore: sessionStore,
            signOutUseCase: signOutUseCase,
            medicalSyncService: medicalSyncService
        )
    }

    func makeAISettingsViewModel() -> AISettingsViewModel {
        AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: aiSettingsRepository),
            saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository)
        )
    }

    func makeChatViewModel() -> ChatViewModel {
        ChatViewModel(
            sessionStore: sessionStore,
            patientContextStore: patientContextStore,
            loadPatientsUseCase: loadPatientsUseCase,
            selectPatientUseCase: selectPatientUseCase,
            loadThreadUseCase: loadChatThreadUseCase,
            createThreadUseCase: createChatThreadUseCase,
            sendMessageUseCase: sendChatMessageUseCase,
            notificationClient: notificationClient
        )
    }
}
