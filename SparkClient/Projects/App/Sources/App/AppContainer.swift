import Foundation

/// 组合根容器：负责初始化基础设施并组装跨 Feature 的依赖关系。
@MainActor
final class AppContainer {
    // MARK: - 基础设施（Core Data、网络、日志、文件）

    let coreDataStack: CoreDataStack
    let backend: Backend
    let logger: Logger
    let fileCacheManager: FileCacheManager
    let fileTransferService: FileTransferService

    // MARK: - 路由与启动

    let routeStore: AppRouteStore
    let appBootstrapper: AppBootstrapper

    // MARK: - 通知（应用内队列、指标、收件箱、远程推送适配）

    let notificationStore: NotificationStore
    let notificationMetricsStore: NotificationMetricsStore
    let notificationInboxStore: NotificationInboxStore
    let notificationQueue: NotificationQueue
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let publishNotificationUseCase: PublishNotificationUseCase
    let notificationClient: any NotificationClient
    let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    let pushAdapter: PushAdapter

    // MARK: - 数据仓库

    let userProfileRepository: any UserProfileRepository
    let healthMetricsRepository: any HealthMetricsRepository
    let authRepository: any AuthRepository
    let aiSettingsRepository: any AISettingsRepository
    /// 本地知识库持久化（Core Data：`KnowledgeDocumentEntity` / `KnowledgeChunkEntity`）。
    let knowledgeRepository: any KnowledgeRepository
    let localModelService: LocalModelService

    // MARK: - 用例（认证、首页、健康、患者、病历草稿、聊天）

    let restoreSessionUseCase: RestoreSessionUseCase
    let signInWithAppleUseCase: SignInWithAppleUseCase
    let signOutUseCase: SignOutUseCase
    let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    let loadHomeMotionHealthUseCase: LoadHomeMotionHealthUseCase
    let manageHomeMemberUseCase: ManageHomeMemberUseCase
    let requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase
    let loadHealthTimelineUseCase: LoadHealthTimelineUseCase
    let loadKnowledgeListUseCase: LoadKnowledgeListUseCase
    let loadKnowledgeDocumentUseCase: LoadKnowledgeDocumentUseCase
    let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    let updateKnowledgeDocumentUseCase: UpdateKnowledgeDocumentUseCase
    let deleteKnowledgeDocumentUseCase: DeleteKnowledgeDocumentUseCase
    let searchKnowledgeUseCase: SearchKnowledgeUseCase
    let reindexKnowledgeDocumentUseCase: ReindexKnowledgeDocumentUseCase
    /// OpenAI 兼容嵌入 HTTP 客户端（知识切块向量化与语义检索查询向量共用）。
    let knowledgeEmbeddingClient: any KnowledgeEmbeddingClient
    let buildKnowledgeEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase
    let polishKnowledgeTextUseCase: PolishKnowledgeTextUseCase
    let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    let ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase
    let importKnowledgeFromFileUseCase: ImportKnowledgeFromFileUseCase
    let importKnowledgeFromWebUseCase: ImportKnowledgeFromWebUseCase
    let loadPatientsUseCase: LoadPatientsUseCase
    let selectPatientUseCase: SelectPatientUseCase
    let extractMedicalDraftFromDocumentUseCase: ExtractMedicalDraftFromDocumentUseCase
    let confirmMedicalDraftUseCase: ConfirmMedicalDraftUseCase
    let loadLatestMedicalDraftUseCase: LoadLatestMedicalDraftUseCase
    let startMedicalDocumentRecognitionUseCase: StartMedicalDocumentRecognitionUseCase
    let saveRecognizedMedicalDocumentUseCase: SaveRecognizedMedicalDocumentUseCase
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase
    let loadChatThreadsUseCase: LoadChatThreadsUseCase
    let loadChatMessagesUseCase: LoadChatMessagesUseCase
    let createThreadUseCase: CreateThreadUseCase
    let retryFailedMessageUseCase: RetryFailedMessageUseCase
    let deleteThreadUseCase: DeleteThreadUseCase
    let syncChatUseCase: SyncChatUseCase
    let sendChatMessageUseCase: SendChatMessageUseCase

    // MARK: - AI 运行时、工具编排、医疗同步、OCR

    let aiRuntimeStore: AIRuntimeStore
    let aiConfigCenter: AIConfigCenter
    let aiRuntimeService: AIRuntimeService
    let toolHub: ToolHub
    let toolAuditStore: ToolAuditStore
    let medicalSyncService: MedicalSyncService
    let ocrOrchestrator: OCROrchestrator

    // MARK: - 会话、患者上下文与聊天界面 ViewModel

    let sessionStore: AppSessionStore
    let patientContextStore: PatientContextStore
    let chatStateStore: ChatStateStore
    let knowledgeViewModel: KnowledgeLibraryViewModel
    let chatListViewModel: ChatListViewModel
    let chatDetailViewModel: ChatDetailViewModel

    init(
        coreDataStack: CoreDataStack,
        backend: Backend,
        ocrConfiguration: OCRConfiguration = OCRConfiguration(),
        logger: Logger = ConsoleLogger()
    ) {
        // 基础设施
        self.coreDataStack = coreDataStack
        self.backend = backend
        self.logger = logger
        self.fileCacheManager = FileCacheManager(logger: logger)
        self.fileTransferService = FileTransferService(api: backend.files, cacheManager: fileCacheManager, logger: logger)

        // 仓库在此统一装配；界面层 ViewModel 只依赖用例，不直接拿仓库。
        let profileRepository = SessionBackedUserProfileRepository()
        let healthMetricsRepository = RemoteHealthMetricsRepository(remoteAPI: backend.medicalSync)
        let authRepository = DefaultAuthRepository(
            backend: backend,
            userProfileRepository: profileRepository,
            healthMetricsRepository: healthMetricsRepository,
            logger: logger
        )
        let aiSettingsRepository = DefaultAISettingsRepository(logger: logger)
        // 知识库：独立仓库，与 AI 设置快照中的 `promptRepo` 解耦。
        let knowledgeRepository = CoreDataKnowledgeRepository(coreDataStack: coreDataStack, logger: logger)
        let knowledgeEmbeddingClient = OpenAICompatibleEmbeddingClient()
        let aiRuntimeStore = AIRuntimeStore()
        let localModelService = LocalModelService()
        let remoteConfigProvider = BackendAIRemoteConfigProvider(api: backend.aiConfig)
        let medicalSyncPreferenceRepository = DefaultMedicalSyncPreferenceRepository()
        let medicalDataRepository = DefaultMedicalDataRepository(
            remoteAPI: backend.medicalSync,
            logger: logger
        )
        let homeMemberRepository = DefaultHomeMemberRepository(
            medicalDataRepository: medicalDataRepository,
            memberAPI: backend.medicalMembers,
            logger: logger
        )
        let homeHealthRepository = HealthKitHomeHealthDataRepository()

        // AI 配置中心（本地设置 + 远程配置 + 运行时状态）
        let aiConfigCenter = AIConfigCenter(
            repository: aiSettingsRepository,
            remoteProvider: remoteConfigProvider,
            runtimeStore: aiRuntimeStore,
            logger: logger
        )

        // OCR：按配置启用阿里云 / 本地服务引擎，再由编排器统一调度
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
        let ocrKnowledgeImageUseCase = OCRKnowledgeImageUseCase(ocr: ocrOrchestrator)
        let importKnowledgeFromFileUseCase = ImportKnowledgeFromFileUseCase()
        let importKnowledgeFromWebUseCase = ImportKnowledgeFromWebUseCase()

        // 大模型调用网关与服务
        let aiRuntimeGateway = OpenAICompatibleTextGateway(logger: logger)
        let localRuntimeGateway = LocalGGUFTextGateway(
            localModelService: localModelService,
            logger: logger
        )
        let aiRuntimeService = AIRuntimeService(
            configCenter: aiConfigCenter,
            gateway: aiRuntimeGateway,
            localGateway: localRuntimeGateway,
            logger: logger
        )
        let polishKnowledgeTextUseCase = PolishKnowledgeTextUseCase(runtime: aiRuntimeService)
        let translateKnowledgeTextUseCase = TranslateKnowledgeTextUseCase(runtime: aiRuntimeService)

        // 患者、病历与「从文档提取草稿」相关用例
        let loadKnowledgeListUseCase = LoadKnowledgeListUseCase(repository: knowledgeRepository)
        let loadKnowledgeDocumentUseCase = LoadKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let createKnowledgeDocumentUseCase = CreateKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let updateKnowledgeDocumentUseCase = UpdateKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let deleteKnowledgeDocumentUseCase = DeleteKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let searchKnowledgeUseCase = SearchKnowledgeUseCase(
            repository: knowledgeRepository,
            aiSettingsRepository: aiSettingsRepository,
            embeddingClient: knowledgeEmbeddingClient
        )
        let reindexKnowledgeDocumentUseCase = ReindexKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let buildKnowledgeEmbeddingsUseCase = BuildKnowledgeEmbeddingsUseCase(
            repository: knowledgeRepository,
            aiSettingsRepository: aiSettingsRepository,
            embeddingClient: knowledgeEmbeddingClient
        )

        let patientRepository = DefaultPatientRepository(medicalDataRepository: medicalDataRepository)
        let medicalRecordRepository = DefaultMedicalRecordRepository(medicalDataRepository: medicalDataRepository)
        let buildPatientContextSummaryUseCase = BuildPatientContextSummaryUseCase(repository: medicalRecordRepository)
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
        let medicalPromptFactory = MedicalPromptFactory()
        let medicalDocumentRecognizer = DefaultMedicalDocumentRecognizer(
            ocrOrchestrator: ocrOrchestrator,
            runtimeService: aiRuntimeService,
            promptBuilder: medicalPromptFactory,
            logger: logger
        )
        let medicalDocumentSaver = DefaultMedicalDocumentSaver(medicalDataRepository: medicalDataRepository)
        let startMedicalDocumentRecognitionUseCase = StartMedicalDocumentRecognitionUseCase(
            recognizer: medicalDocumentRecognizer
        )
        let saveRecognizedMedicalDocumentUseCase = SaveRecognizedMedicalDocumentUseCase(
            saver: medicalDocumentSaver
        )

        // 聊天侧可调用的工具集合（含审计）
        let toolAuditStore = ToolAuditStore()
        let toolHub = ToolHub(
            extractDraftUseCase: extractMedicalDraftFromDocumentUseCase,
            confirmDraftUseCase: confirmMedicalDraftUseCase,
            loadLatestDraftUseCase: loadLatestMedicalDraftUseCase,
            auditStore: toolAuditStore,
            medicalDataRepository: medicalDataRepository,
            healthMetricsRepository: healthMetricsRepository,
            aiSettingsRepository: aiSettingsRepository,
            searchKnowledgeUseCase: searchKnowledgeUseCase,
            createKnowledgeDocumentUseCase: createKnowledgeDocumentUseCase,
            logger: logger
        )

        // 聊天：Core Data 仓库、离线与实时同步、编排发送
        let chatRepository = CoreDataChatRepository(coreDataStack: coreDataStack, logger: logger)
        let chatOutboxStore = ChatOutboxStore(repository: chatRepository)
        let chatRealtimeClient = ChatRealtimeSyncClient(
            tokenProvider: backend.tokenProvider(),
            baseURL: backend.baseURL,
            logger: logger
        )
        let chatSyncEngine = ChatSyncEngine(
            repository: chatRepository,
            outboxStore: chatOutboxStore,
            remoteAPI: backend.chat,
            realtimeClient: chatRealtimeClient,
            mergePolicy: ChatMergePolicy(),
            logger: logger
        )
        let chatOrchestrator = ChatOrchestrator(
            runtimeService: aiRuntimeService,
            toolHub: toolHub,
            consentGate: ConsentGate(),
            logger: logger
        )
        let loadChatThreadsUseCase = LoadChatThreadsUseCase(repository: chatRepository)
        let loadChatMessagesUseCase = LoadChatMessagesUseCase(repository: chatRepository)
        let createThreadUseCase = CreateThreadUseCase(repository: chatRepository)
        let retryFailedMessageUseCase = RetryFailedMessageUseCase(
            repository: chatRepository,
            syncEngine: chatSyncEngine,
            logger: logger
        )
        let deleteThreadUseCase = DeleteThreadUseCase(repository: chatRepository)
        let syncChatUseCase = SyncChatUseCase(syncEngine: chatSyncEngine)
        let sendChatMessageUseCase = SendChatMessageUseCase(
            repository: chatRepository,
            orchestrator: chatOrchestrator,
            syncEngine: chatSyncEngine,
            buildPatientContextSummaryUseCase: buildPatientContextSummaryUseCase,
            logger: logger
        )

        // 应用内通知管道与远程推送处理
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

        // 医疗数据后台同步（可发本地通知）
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

        // 冷启动：拉 AI 配置、同步医疗与聊天等
        let appBootstrapper = AppBootstrapper(
            aiConfigCenter: aiConfigCenter,
            medicalSyncService: medicalSyncService,
            syncChatUseCase: syncChatUseCase,
            routeStore: routeStore,
            logger: logger
        )

        // 将局部变量赋给实例属性（对外暴露）
        self.userProfileRepository = profileRepository
        self.healthMetricsRepository = healthMetricsRepository
        self.authRepository = authRepository
        self.aiSettingsRepository = aiSettingsRepository
        self.knowledgeRepository = knowledgeRepository
        self.localModelService = localModelService

        self.restoreSessionUseCase = RestoreSessionUseCase(authRepository: authRepository)
        self.signInWithAppleUseCase = SignInWithAppleUseCase(authRepository: authRepository)
        self.signOutUseCase = SignOutUseCase(authRepository: authRepository)
        self.loadHomeMedicalOverviewUseCase = LoadHomeMedicalOverviewUseCase(
            userProfileRepository: profileRepository,
            memberRepository: homeMemberRepository,
            logger: logger
        )
        self.loadHomeMotionHealthUseCase = LoadHomeMotionHealthUseCase(
            healthDataRepository: homeHealthRepository,
            logger: logger
        )
        self.manageHomeMemberUseCase = ManageHomeMemberUseCase(memberRepository: homeMemberRepository)
        self.requestHomeHealthAuthorizationUseCase = RequestHomeHealthAuthorizationUseCase(healthDataRepository: homeHealthRepository)
        self.loadHealthTimelineUseCase = LoadHealthTimelineUseCase(healthMetricsRepository: healthMetricsRepository)
        self.loadKnowledgeListUseCase = loadKnowledgeListUseCase
        self.loadKnowledgeDocumentUseCase = loadKnowledgeDocumentUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.updateKnowledgeDocumentUseCase = updateKnowledgeDocumentUseCase
        self.deleteKnowledgeDocumentUseCase = deleteKnowledgeDocumentUseCase
        self.searchKnowledgeUseCase = searchKnowledgeUseCase
        self.reindexKnowledgeDocumentUseCase = reindexKnowledgeDocumentUseCase
        self.knowledgeEmbeddingClient = knowledgeEmbeddingClient
        self.buildKnowledgeEmbeddingsUseCase = buildKnowledgeEmbeddingsUseCase
        self.polishKnowledgeTextUseCase = polishKnowledgeTextUseCase
        self.translateKnowledgeTextUseCase = translateKnowledgeTextUseCase
        self.ocrKnowledgeImageUseCase = ocrKnowledgeImageUseCase
        self.importKnowledgeFromFileUseCase = importKnowledgeFromFileUseCase
        self.importKnowledgeFromWebUseCase = importKnowledgeFromWebUseCase
        self.loadPatientsUseCase = LoadPatientsUseCase(repository: patientRepository)
        self.selectPatientUseCase = SelectPatientUseCase()
        self.extractMedicalDraftFromDocumentUseCase = extractMedicalDraftFromDocumentUseCase
        self.confirmMedicalDraftUseCase = confirmMedicalDraftUseCase
        self.loadLatestMedicalDraftUseCase = loadLatestMedicalDraftUseCase
        self.startMedicalDocumentRecognitionUseCase = startMedicalDocumentRecognitionUseCase
        self.saveRecognizedMedicalDocumentUseCase = saveRecognizedMedicalDocumentUseCase
        self.buildPatientContextSummaryUseCase = buildPatientContextSummaryUseCase
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.createThreadUseCase = createThreadUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.syncChatUseCase = syncChatUseCase
        self.sendChatMessageUseCase = sendChatMessageUseCase

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

        // 会话与聊天列表/详情共用状态与 ViewModel（单例式挂载，便于跨屏共享）
        self.sessionStore = AppSessionStore(restoreSessionUseCase: restoreSessionUseCase)
        self.patientContextStore = patientContextStore
        self.chatStateStore = ChatStateStore()
        self.knowledgeViewModel = KnowledgeLibraryViewModel(
            loadListUseCase: loadKnowledgeListUseCase,
            loadDocumentUseCase: loadKnowledgeDocumentUseCase,
            createUseCase: createKnowledgeDocumentUseCase,
            updateUseCase: updateKnowledgeDocumentUseCase,
            deleteUseCase: deleteKnowledgeDocumentUseCase,
            searchUseCase: searchKnowledgeUseCase,
            reindexUseCase: reindexKnowledgeDocumentUseCase
        )
        self.chatListViewModel = ChatListViewModel(
            stateStore: chatStateStore,
            sessionStore: sessionStore,
            patientContextStore: patientContextStore,
            loadPatientsUseCase: loadPatientsUseCase,
            selectPatientUseCase: selectPatientUseCase,
            loadChatThreadsUseCase: loadChatThreadsUseCase,
            loadChatMessagesUseCase: loadChatMessagesUseCase,
            createThreadUseCase: createThreadUseCase,
            deleteThreadUseCase: deleteThreadUseCase,
            notificationClient: notificationClient
        )
        self.chatDetailViewModel = ChatDetailViewModel(
            stateStore: chatStateStore,
            patientContextStore: patientContextStore,
            loadChatThreadsUseCase: loadChatThreadsUseCase,
            loadChatMessagesUseCase: loadChatMessagesUseCase,
            sendMessageUseCase: sendChatMessageUseCase,
            retryFailedMessageUseCase: retryFailedMessageUseCase,
            syncChatUseCase: syncChatUseCase,
            notificationClient: notificationClient,
            aiConfigCenter: aiConfigCenter,
            aiSettingsRepository: aiSettingsRepository,
            logger: logger
        )
    }

    /// 生产环境：读取当前 `AppEnvironment`，使用共享 Core Data 与真实 API 基址。
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

    /// SwiftUI 预览：独立子系统日志、预览用 Core Data、占位 API 地址。
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

    // MARK: - ViewModel 工厂（按界面装配依赖）

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(
            signInWithAppleUseCase: signInWithAppleUseCase,
            sessionStore: sessionStore
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            sessionStore: sessionStore,
            loadHomeMedicalOverviewUseCase: loadHomeMedicalOverviewUseCase,
            loadHomeMotionHealthUseCase: loadHomeMotionHealthUseCase,
            manageHomeMemberUseCase: manageHomeMemberUseCase,
            requestHomeHealthAuthorizationUseCase: requestHomeHealthAuthorizationUseCase,
            patientContextStore: patientContextStore,
            notificationClient: notificationClient,
            logger: logger
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

    func makeMedicalDocumentUploadViewModel() -> MedicalDocumentUploadViewModel {
        MedicalDocumentUploadViewModel(
            patientContextStore: patientContextStore,
            startUseCase: startMedicalDocumentRecognitionUseCase,
            saveUseCase: saveRecognizedMedicalDocumentUseCase
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
            saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository),
            localModelService: localModelService,
            aiConfigAPI: backend.aiConfig
        )
    }

    func makeChatStateStore() -> ChatStateStore {
        chatStateStore
    }

    func makeKnowledgeLibraryViewModel() -> KnowledgeLibraryViewModel {
        knowledgeViewModel
    }

    /// 知识文档「写作页」专用 ViewModel（按文档 ID 注入用例）。
    func makeKnowledgeDocumentEditorViewModel(documentID: UUID) -> KnowledgeDocumentEditorViewModel {
        KnowledgeDocumentEditorViewModel(
            documentID: documentID,
            loadListUseCase: loadKnowledgeListUseCase,
            loadDocumentUseCase: loadKnowledgeDocumentUseCase,
            updateDocumentUseCase: updateKnowledgeDocumentUseCase,
            deleteDocumentUseCase: deleteKnowledgeDocumentUseCase,
            buildEmbeddingsUseCase: buildKnowledgeEmbeddingsUseCase,
            polishUseCase: polishKnowledgeTextUseCase,
            translateUseCase: translateKnowledgeTextUseCase,
            ocrUseCase: ocrKnowledgeImageUseCase,
            importFileUseCase: importKnowledgeFromFileUseCase,
            importWebUseCase: importKnowledgeFromWebUseCase,
            aiSettingsRepository: aiSettingsRepository,
            logger: logger
        )
    }

    func makeChatListViewModel() -> ChatListViewModel {
        chatListViewModel
    }

    func makeChatDetailViewModel() -> ChatDetailViewModel {
        chatDetailViewModel
    }
}
