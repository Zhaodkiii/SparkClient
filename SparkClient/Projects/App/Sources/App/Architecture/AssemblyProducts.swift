import Foundation

/// App 级基础设施装配产物。
struct AppInfrastructureAssemblyProduct {
    let taskService: TaskService
    let taskManager: TaskManager
    let taskRuntime: any TaskRuntimeSyncing
    let storageRegistry: StorageRegistry
    let fileCacheManager: FileCacheManager
    let ossConfigurationStore: SparkOSSConfigurationStore
    let fileTransferService: FileTransferService
}

/// 认证领域装配产物。
struct AuthAssemblyProduct {
    let userProfileRepository: any UserProfileRepository
    let selectedMemberIDPersistence: any SelectedMemberIDPersisting
    let sessionSnapshotStore: SessionSnapshotStore
    let authRepository: any AuthRepository
    let restoreSessionUseCase: RestoreSessionUseCase
    let signInWithAppleUseCase: SignInWithAppleUseCase
    let requestPhoneOTPUseCase: RequestPhoneOTPUseCase
    let signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase
    let signOutUseCase: SignOutUseCase
}

/// AI 领域装配产物：持久配置、运行时缓存、云端/本地模型网关统一在这里创建。
struct AIAssemblyProduct {
    let aiSettingsRepository: any AISettingsRepository
    let knowledgeEmbeddingClient: any KnowledgeEmbeddingClient
    let aiRuntimeStore: AIRuntimeStore
    let aiConfigCenter: AIConfigCenter
    let aiRuntimeService: AIRuntimeService
    let localModelService: LocalModelService
    let polishKnowledgeTextUseCase: PolishKnowledgeTextUseCase
    let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    let autoFillAgentPromptUseCase: AutoFillAgentPromptUseCase
}

/// 知识库领域装配产物。
struct KnowledgeAssemblyProduct {
    let knowledgeRepository: any KnowledgeRepository
    let loadKnowledgeListUseCase: LoadKnowledgeListUseCase
    let loadKnowledgeDocumentUseCase: LoadKnowledgeDocumentUseCase
    let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    let updateKnowledgeDocumentUseCase: UpdateKnowledgeDocumentUseCase
    let deleteKnowledgeDocumentUseCase: DeleteKnowledgeDocumentUseCase
    let searchKnowledgeUseCase: SearchKnowledgeUseCase
    let reindexKnowledgeDocumentUseCase: ReindexKnowledgeDocumentUseCase
    let buildKnowledgeEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase
    let ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase
    let importKnowledgeFromFileUseCase: ImportKnowledgeFromFileUseCase
    let importKnowledgeFromWebUseCase: ImportKnowledgeFromWebUseCase
}

/// 医疗领域装配产物。
struct MedicalAssemblyProduct {
    let ocrOrchestrator: OCROrchestrator
    let medicalSyncPreferenceRepository: DefaultMedicalSyncPreferenceRepository
    let membersRepository: DefaultMembersRepository
    let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    let manageHomeMemberUseCase: ManageHomeMemberUseCase
    let buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase
    let loadMembersUseCase: LoadMembersUseCase
    let selectMemberUseCase: SelectMemberUseCase
    let uploadMedicalDocumentFilesUseCase: UploadMedicalDocumentFilesUseCase
    let extractTypedMedicalDocumentUseCase: ExtractTypedMedicalDocumentUseCase
    let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    let bindUploadedFilesToMedicalBusinessUseCase: BindUploadedFilesToMedicalBusinessUseCase
    let typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor
}

/// 通知、路由、Push、医疗后台同步装配产物。
struct NotificationAssemblyProduct {
    let routeStore: AppRouteStore
    let routeCoordinator: RouteCoordinator
    let memberContextStore: MemberContextStore
    let notificationStore: NotificationStore
    let notificationMetricsStore: NotificationMetricsStore
    let notificationInboxStore: NotificationInboxStore
    let notificationQueue: NotificationQueue
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let publishNotificationUseCase: PublishNotificationUseCase
    let notificationClient: any NotificationClient
    let medicalSyncService: MedicalSyncService
    let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    let registerDeviceUseCase: RegisterDeviceUseCase
    let pushAdapter: PushAdapter
}

/// 聊天领域装配产物。
struct ChatAssemblyProduct {
    let chatRepository: CoreDataChatRepository
    let structuredHealthCardMergeCoordinator: StructuredHealthCardMergeCoordinator
    let toolAuditStore: ToolAuditStore
    let toolHub: ToolHub
    let chatQueryService: ChatQueryService
    let loadChatThreadsUseCase: LoadChatThreadsUseCase
    let loadChatMessagesUseCase: LoadChatMessagesUseCase
    let createThreadUseCase: CreateThreadUseCase
    let retryFailedMessageUseCase: RetryFailedMessageUseCase
    let updateChatMessageAttachmentsUseCase: UpdateChatMessageAttachmentsUseCase
    let deleteThreadUseCase: DeleteThreadUseCase
    let syncChatUseCase: SyncChatUseCase
    let chatSyncSupervisor: ChatSyncSupervisor
    let sendChatMessageUseCase: SendChatMessageUseCase
}

extension AppAssembly {
    /// 创建 appSingleton 基础设施。这里仍允许封装系统 singleton，但对外只暴露协议/facade。
    static func makeInfrastructure(
        backend: Backend,
        logger: Logger
    ) -> AppInfrastructureAssemblyProduct {
        logger.info("AppAssembly 装配基础设施开始", module: .general)
        let taskService = TaskService(configuration: backend.configuration, logger: logger)
        let taskManager = TaskManager.shared
        taskManager.configure(taskService: taskService, logger: logger)

        let fileCacheManager = FileCacheManager(logger: logger)
        let ossConfigurationStore = SparkOSSConfigurationStore(logger: logger)
        let ossManager = OSSManager.shared
        let ossClient = OSSClientWrapper(manager: ossManager)
        ossManager.credentialsProvider = { [weak ossConfigurationStore, backend] in
            guard let store = ossConfigurationStore else {
                throw SparkOSSConfigurationError.incompleteSTSResponse
            }
            let config = try await store.configurationForUpload(using: backend.oss)
            return OSSCredentials(
                accessKeyId: config.accessKeyId,
                accessKeySecret: config.accessKeySecret,
                securityToken: config.securityToken,
                expiration: config.credentialExpiresAt
            )
        }

        let fileTransferService = FileTransferService(
            api: backend.files,
            ossAPI: backend.oss,
            ossClient: ossClient,
            ossRuntimeConfigurator: ossManager,
            ossConfigurationStore: ossConfigurationStore,
            cacheManager: fileCacheManager,
            logger: logger
        )
        let storageRegistry = StorageRegistry.live(
            fileCacheManager: fileCacheManager,
            fileTransferService: fileTransferService,
            logger: logger
        )
        logger.info("AppAssembly 装配基础设施完成", module: .general)
        return AppInfrastructureAssemblyProduct(
            taskService: taskService,
            taskManager: taskManager,
            taskRuntime: taskManager,
            storageRegistry: storageRegistry,
            fileCacheManager: fileCacheManager,
            ossConfigurationStore: ossConfigurationStore,
            fileTransferService: fileTransferService
        )
    }

    static func makeBootstrapper(
        ai: AIAssemblyProduct,
        notification: NotificationAssemblyProduct,
        chat: ChatAssemblyProduct,
        infrastructure: AppInfrastructureAssemblyProduct,
        backend: Backend,
        logger: Logger
    ) -> AppBootstrapper {
        logger.info("AppAssembly 装配启动协调器", module: .general)
        return AppBootstrapper(
            aiConfigCenter: ai.aiConfigCenter,
            medicalSyncService: notification.medicalSyncService,
            chatSyncSupervisor: chat.chatSyncSupervisor,
            ossConfigurationStore: infrastructure.ossConfigurationStore,
            ossAPI: backend.oss,
            registerDevice: { await notification.registerDeviceUseCase.execute() },
            logger: logger
        )
    }
}

extension AuthAssembly {
    static func makeCore(
        backend: Backend,
        logger: Logger
    ) -> AuthAssemblyProduct {
        logger.info("AuthAssembly 装配认证核心", module: .auth)
        let profileRepository = SessionBackedUserProfileRepository()
        let selectedMemberIDPersistence = UserDefaultsSelectedMemberIDStore()
        let sessionSnapshotStore = SessionSnapshotStore()
        let authRepository = DefaultAuthRepository(
            backend: backend,
            userProfileRepository: profileRepository,
            snapshotStore: sessionSnapshotStore,
            logger: logger
        )
        return AuthAssemblyProduct(
            userProfileRepository: profileRepository,
            selectedMemberIDPersistence: selectedMemberIDPersistence,
            sessionSnapshotStore: sessionSnapshotStore,
            authRepository: authRepository,
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: authRepository),
            signInWithAppleUseCase: SignInWithAppleUseCase(authRepository: authRepository),
            requestPhoneOTPUseCase: RequestPhoneOTPUseCase(authRepository: authRepository),
            signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase(authRepository: authRepository),
            signOutUseCase: SignOutUseCase(authRepository: authRepository)
        )
    }
}

extension AIAssembly {
    static func makeCore(
        coreDataStack: CoreDataStack,
        backend: Backend,
        sessionSnapshotStore: SessionSnapshotStore,
        logger: Logger
    ) -> AIAssemblyProduct {
        logger.info("AIAssembly 装配 AI 配置与运行时", module: .aiConfig)
        let aiSettingsRepository = DefaultAISettingsRepository(
            coreDataStack: coreDataStack,
            snapshotStore: sessionSnapshotStore,
            logger: logger
        )
        let knowledgeEmbeddingClient = OpenAICompatibleEmbeddingClient()
        let aiRuntimeStore = AIRuntimeStore()
        let aiRuntimeConfigStore = AIRuntimeConfigStore()
        let localModelService = LocalModelService()
        let remoteConfigProvider = BackendAIRemoteConfigProvider(api: backend.aiConfig)
        let aiConfigCenter = AIConfigCenter(
            repository: aiSettingsRepository,
            remoteProvider: remoteConfigProvider,
            runtimeStore: aiRuntimeStore,
            runtimeConfigStore: aiRuntimeConfigStore,
            sessionSnapshotStore: sessionSnapshotStore,
            logger: logger
        )
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
        return AIAssemblyProduct(
            aiSettingsRepository: aiSettingsRepository,
            knowledgeEmbeddingClient: knowledgeEmbeddingClient,
            aiRuntimeStore: aiRuntimeStore,
            aiConfigCenter: aiConfigCenter,
            aiRuntimeService: aiRuntimeService,
            localModelService: localModelService,
            polishKnowledgeTextUseCase: PolishKnowledgeTextUseCase(runtime: aiRuntimeService),
            translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase(runtime: aiRuntimeService),
            autoFillAgentPromptUseCase: AutoFillAgentPromptUseCase(runtime: aiRuntimeService)
        )
    }
}

extension MedicalAssembly {
    static func makeCore(
        backend: Backend,
        fileTransferService: FileTransferService,
        userProfileRepository: any UserProfileRepository,
        selectedMemberIDPersistence: any SelectedMemberIDPersisting,
        aiRuntimeService: AIRuntimeService,
        ocrConfiguration: OCRConfiguration,
        logger: Logger
    ) -> MedicalAssemblyProduct {
        logger.info("MedicalAssembly 装配医疗/OCR 核心", module: .medical)
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
        let membersRepository = DefaultMembersRepository(medicalQueryAPI: backend.medicalQuery)
        let medicalRecordRepository = DefaultMedicalRecordRepository(medicalQueryAPI: backend.medicalQuery)
        let buildMemberContextSummaryUseCase = BuildMemberContextSummaryUseCase(repository: medicalRecordRepository)
        let medicalPromptFactory = MedicalPromptFactory()
        let medicalDocumentTypeResolver = DefaultMedicalDocumentTypeResolver(
            runtimeService: aiRuntimeService,
            promptFactory: medicalPromptFactory,
            logger: logger
        )
        let typedMedicalDocumentExtractor = DefaultTypedMedicalDocumentExtractor(
            ocrOrchestrator: ocrOrchestrator,
            typeResolver: medicalDocumentTypeResolver,
            promptFactory: medicalPromptFactory,
            runtimeService: aiRuntimeService,
            logger: logger
        )
        let typedMedicalDocumentSaver = DefaultTypedMedicalDocumentSaver(
            workflowAPI: backend.medicalWorkflow,
            combinedAPI: backend.medicalCombinedCreate,
            logger: logger
        )
        let attachmentBinder = DefaultMedicalDocumentAttachmentBinder(fileAPI: backend.files, logger: logger)
        return MedicalAssemblyProduct(
            ocrOrchestrator: ocrOrchestrator,
            medicalSyncPreferenceRepository: DefaultMedicalSyncPreferenceRepository(),
            membersRepository: membersRepository,
            loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase(
                userProfileRepository: userProfileRepository,
                medicalQueryAPI: backend.medicalQuery,
                selectedMemberIDPersistence: selectedMemberIDPersistence,
                logger: logger
            ),
            manageHomeMemberUseCase: ManageHomeMemberUseCase(memberAPI: backend.medicalMembers),
            buildMemberContextSummaryUseCase: buildMemberContextSummaryUseCase,
            loadMembersUseCase: LoadMembersUseCase(repository: membersRepository),
            selectMemberUseCase: SelectMemberUseCase(),
            uploadMedicalDocumentFilesUseCase: UploadMedicalDocumentFilesUseCase(
                fileTransferService: fileTransferService,
                logger: logger
            ),
            extractTypedMedicalDocumentUseCase: ExtractTypedMedicalDocumentUseCase(
                extractor: typedMedicalDocumentExtractor
            ),
            saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase(
                saver: typedMedicalDocumentSaver
            ),
            bindUploadedFilesToMedicalBusinessUseCase: BindUploadedFilesToMedicalBusinessUseCase(
                binder: attachmentBinder
            ),
            typedMedicalDocumentExtractor: typedMedicalDocumentExtractor
        )
    }
}

extension NotificationAssembly {
    static func makeCore(
        backend: Backend,
        selectedMemberIDPersistence: any SelectedMemberIDPersisting,
        medicalSyncPreferenceRepository: DefaultMedicalSyncPreferenceRepository,
        logger: Logger
    ) -> NotificationAssemblyProduct {
        logger.info("NotificationAssembly 装配通知/Push/路由核心", module: .push)
        let routeStore = AppRouteStore()
        let routeCoordinator = RouteCoordinator(routeStore: routeStore, logger: logger)
        let memberContextStore = MemberContextStore(persistence: selectedMemberIDPersistence)
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
        let notificationClient = DefaultNotificationClient(publishUseCase: publishNotificationUseCase)
        let medicalSyncService = MedicalSyncService(
            preferenceRepository: medicalSyncPreferenceRepository,
            medicalQueryAPI: backend.medicalQuery,
            notificationClient: notificationClient,
            logger: logger
        )
        let handleRemoteNotificationUseCase = HandleRemoteNotificationUseCase(
            routeCoordinator: routeCoordinator,
            notificationClient: notificationClient
        )
        let registerDeviceUseCase = RegisterDeviceUseCase(backend: backend, logger: logger)
        let pushAdapter = PushAdapter(
            handleRemoteNotificationUseCase: handleRemoteNotificationUseCase,
            notificationCenter: SystemRemoteNotificationCenterClient(),
            logger: logger,
            onApnsTokenHex: { hex in
                await registerDeviceUseCase.execute(pushToken: hex, notificationsEnabled: true)
            },
            onRemoteNotificationAuthorizationResolved: { granted in
                if granted {
                    // 用户同意后先标记通知开启；APNs token 回调再写入真实 token，避免覆盖旧值。
                    await registerDeviceUseCase.execute(pushToken: nil, notificationsEnabled: true)
                } else {
                    // 用户拒绝或权限异常时，服务端同步关闭推送并清空 token。
                    await registerDeviceUseCase.execute(pushToken: "", notificationsEnabled: false)
                }
            }
        )
        return NotificationAssemblyProduct(
            routeStore: routeStore,
            routeCoordinator: routeCoordinator,
            memberContextStore: memberContextStore,
            notificationStore: notificationStore,
            notificationMetricsStore: notificationMetricsStore,
            notificationInboxStore: notificationInboxStore,
            notificationQueue: notificationQueue,
            notificationDeliveryCoordinator: notificationDeliveryCoordinator,
            publishNotificationUseCase: publishNotificationUseCase,
            notificationClient: notificationClient,
            medicalSyncService: medicalSyncService,
            handleRemoteNotificationUseCase: handleRemoteNotificationUseCase,
            registerDeviceUseCase: registerDeviceUseCase,
            pushAdapter: pushAdapter
        )
    }
}

extension AIAssembly {
    static func makeKnowledge(
        coreDataStack: CoreDataStack,
        ai: AIAssemblyProduct,
        ocrOrchestrator: OCROrchestrator,
        logger: Logger
    ) -> KnowledgeAssemblyProduct {
        logger.info("AIAssembly 装配知识库核心", module: .aiConfig)
        let knowledgeRepository = CoreDataKnowledgeRepository(coreDataStack: coreDataStack, logger: logger)
        let loadKnowledgeListUseCase = LoadKnowledgeListUseCase(repository: knowledgeRepository)
        let loadKnowledgeDocumentUseCase = LoadKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let createKnowledgeDocumentUseCase = CreateKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let updateKnowledgeDocumentUseCase = UpdateKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let deleteKnowledgeDocumentUseCase = DeleteKnowledgeDocumentUseCase(repository: knowledgeRepository)
        let searchKnowledgeUseCase = SearchKnowledgeUseCase(
            repository: knowledgeRepository,
            aiConfigCenter: ai.aiConfigCenter,
            embeddingClient: ai.knowledgeEmbeddingClient
        )
        return KnowledgeAssemblyProduct(
            knowledgeRepository: knowledgeRepository,
            loadKnowledgeListUseCase: loadKnowledgeListUseCase,
            loadKnowledgeDocumentUseCase: loadKnowledgeDocumentUseCase,
            createKnowledgeDocumentUseCase: createKnowledgeDocumentUseCase,
            updateKnowledgeDocumentUseCase: updateKnowledgeDocumentUseCase,
            deleteKnowledgeDocumentUseCase: deleteKnowledgeDocumentUseCase,
            searchKnowledgeUseCase: searchKnowledgeUseCase,
            reindexKnowledgeDocumentUseCase: ReindexKnowledgeDocumentUseCase(repository: knowledgeRepository),
            buildKnowledgeEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase(
                repository: knowledgeRepository,
                aiConfigCenter: ai.aiConfigCenter,
                embeddingClient: ai.knowledgeEmbeddingClient
            ),
            ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase(ocr: ocrOrchestrator),
            importKnowledgeFromFileUseCase: ImportKnowledgeFromFileUseCase(),
            importKnowledgeFromWebUseCase: ImportKnowledgeFromWebUseCase()
        )
    }
}

extension ChatAssembly {
    static func makeCore(
        coreDataStack: CoreDataStack,
        backend: Backend,
        infrastructure: AppInfrastructureAssemblyProduct,
        ai: AIAssemblyProduct,
        knowledge: KnowledgeAssemblyProduct,
        medical: MedicalAssemblyProduct,
        logger: Logger
    ) -> ChatAssemblyProduct {
        logger.info("ChatAssembly 装配聊天核心", module: .general)
        let chatRepository = CoreDataChatRepository(coreDataStack: coreDataStack, logger: logger)
        let structuredHealthCardMergeCoordinator = StructuredHealthCardMergeCoordinator(repository: chatRepository)
        let toolAuditStore = ToolAuditStore()
        let toolHub = ToolHub(
            chatRepository: chatRepository,
            auditStore: toolAuditStore,
            medicalQueryAPI: backend.medicalQuery,
            aiSettingsRepository: ai.aiSettingsRepository,
            aiConfigCenter: ai.aiConfigCenter,
            runtimeService: ai.aiRuntimeService,
            taskService: infrastructure.taskService,
            searchKnowledgeUseCase: knowledge.searchKnowledgeUseCase,
            createKnowledgeDocumentUseCase: knowledge.createKnowledgeDocumentUseCase,
            typedMedicalDocumentExtractor: medical.typedMedicalDocumentExtractor,
            structuredHealthCardMergeCoordinator: structuredHealthCardMergeCoordinator,
            logger: logger
        )
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
        let chatAttachmentPipeline = ChatAttachmentPipeline(
            repository: chatRepository,
            fileTransferService: infrastructure.fileTransferService,
            logger: logger
        )
        let chatSyncSupervisor = ChatSyncSupervisor(
            syncEngine: chatSyncEngine,
            attachmentPipeline: chatAttachmentPipeline
        )
        let chatOrchestrator = ChatOrchestrator(
            runtimeService: ai.aiRuntimeService,
            toolHub: toolHub,
            consentGate: ConsentGate(),
            fileCacheManager: infrastructure.fileCacheManager,
            logger: logger
        )
        let chatQueryService = ChatQueryService(repository: chatRepository)
        let syncChatUseCase = SyncChatUseCase(supervisor: chatSyncSupervisor)
        let updateChatMessageAttachmentsUseCase = UpdateChatMessageAttachmentsUseCase(repository: chatRepository)
        let sendChatMessageUseCase = SendChatMessageUseCase(
            repository: chatRepository,
            orchestrator: chatOrchestrator,
            chatSyncSupervisor: chatSyncSupervisor,
            buildMemberContextSummaryUseCase: medical.buildMemberContextSummaryUseCase,
            toolEventInterpreter: ChatToolEventInterpreter(logger: logger),
            fileTransferService: infrastructure.fileTransferService,
            ocrOrchestrator: medical.ocrOrchestrator,
            aiConfigCenter: ai.aiConfigCenter,
            logger: logger
        )
        return ChatAssemblyProduct(
            chatRepository: chatRepository,
            structuredHealthCardMergeCoordinator: structuredHealthCardMergeCoordinator,
            toolAuditStore: toolAuditStore,
            toolHub: toolHub,
            chatQueryService: chatQueryService,
            loadChatThreadsUseCase: LoadChatThreadsUseCase(queryService: chatQueryService),
            loadChatMessagesUseCase: LoadChatMessagesUseCase(queryService: chatQueryService),
            createThreadUseCase: CreateThreadUseCase(repository: chatRepository, aiConfigCenter: ai.aiConfigCenter, syncChatUseCase: syncChatUseCase),
            retryFailedMessageUseCase: RetryFailedMessageUseCase(
                repository: chatRepository,
                chatSyncSupervisor: chatSyncSupervisor,
                logger: logger
            ),
            updateChatMessageAttachmentsUseCase: updateChatMessageAttachmentsUseCase,
            deleteThreadUseCase: DeleteThreadUseCase(
                repository: chatRepository,
                chatSyncSupervisor: chatSyncSupervisor
            ),
            syncChatUseCase: syncChatUseCase,
            chatSyncSupervisor: chatSyncSupervisor,
            sendChatMessageUseCase: sendChatMessageUseCase
        )
    }
}
