import Foundation

/// 应用的**组合根（Composition Root）**：在单一位置创建并持有几乎全部跨模块依赖，避免 Feature 层互相 `import` 具体实现。
///
/// ### 设计要点
/// - 使用 `@MainActor` 与 SwiftUI 生命周期对齐，工厂方法创建的 ViewModel 可在主线程安全使用。
/// - **依赖方向**：UI → ViewModel → UseCase → Repository / API；容器负责把「接口」绑到「默认实现」（如 `DefaultAuthRepository`）。
/// - **单例式 ViewModel**（聊天列表/详情、知识库）：跨界面共享状态，故在 `init` 末尾直接挂到属性上，而不是每次 `make*` 新建。
/// - **预览与生产**：`live()` 读 `AppEnvironment`；`preview` 使用独立子系统与占位 URL，避免污染真机数据。
///
/// ### 初始化顺序（阅读 `init` 时可参考）
/// 1. 基础设施（Core Data、Backend、日志、文件缓存与上传）。
/// 2. 各 Repository 与「纯数据访问」依赖。
/// 3. AI 配置中心、OCR 编排、大模型运行时。
/// 4. 知识库 / 患者 / 病历草稿 / 结构化病历上传 等用例链。
/// 5. 聊天仓库、同步引擎、发送编排。
/// 6. 应用内通知、医疗后台同步、推送适配、冷启动 `AppBootstrapper`（含登录后 OSS STS 预拉取）。
/// 7. 将局部变量赋给 `self` 属性，再构造会话 Store 与共享 ViewModel。
@MainActor
final class AppContainer {
    // MARK: - 基础设施（Core Data、网络、日志、文件）
    //
    // `CoreDataStack`：聊天消息、知识文档等本地持久化入口。
    // `Backend`：聚合各域 API（医疗查询、文件、聊天、AI 配置等）与 token、基址。
    // `FileCacheManager` + `FileTransferService`：下载缓存与上传任务，供病历附件等使用。

    /// 本地持久化栈（共享或预览实例由 `live()` / `preview` 注入）。
    let coreDataStack: CoreDataStack
    /// 后端 API 聚合与鉴权上下文。
    let backend: Backend
    /// 全局日志器；各层默认传入同一实例便于过滤 subsystem。
    let logger: Logger
    /// 文件缓存目录与元数据管理。
    let fileCacheManager: FileCacheManager
    /// 基于 `backend.files` 的上传/下载编排。
    let fileTransferService: FileTransferService
    /// 登录后预拉取的 OSS STS 与桶信息；直传前可调用 `configurationForUpload(using:)` 自动续期。
    let ossConfigurationStore: SparkOSSConfigurationStore

    // MARK: - 路由与启动
    //
    // `AppRouteStore`：深链/推送解析后的待处理路由。
    // `AppBootstrapper`：冷启动时拉远程配置、触发医疗同步与聊天同步等。

    /// 待处理导航目标（例如从通知点进某页）。
    let routeStore: AppRouteStore
    /// 应用启动阶段副作用（非 UI）的集中入口。
    let appBootstrapper: AppBootstrapper
    /// 设备登记（匿名或带 JWT，与冷启动 / 登录后 / APNs token 联动）。
    let registerDeviceUseCase: RegisterDeviceUseCase

    // MARK: - 通知（应用内队列、指标、收件箱、远程推送适配）
    //
    // 内部分层：队列 → 投递协调器 → Store；`NotificationClient` 是对外的精简门面。
    // 远程推送经 `HandleRemoteNotificationUseCase` 再入队，由 `PushAdapter` 对接系统回调。

    /// 当前应展示的横幅/Toast 等（由协调器写入）。
    let notificationStore: NotificationStore
    /// 送达、点击等指标统计。
    let notificationMetricsStore: NotificationMetricsStore
    /// 收件箱式通知列表数据源。
    let notificationInboxStore: NotificationInboxStore
    /// 串行化处理通知任务、削峰。
    let notificationQueue: NotificationQueue
    /// 连接 queue 与各 Store 的桥。
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    /// Feature 发布一条应用内通知的用例。
    let publishNotificationUseCase: PublishNotificationUseCase
    /// 对 UI/业务暴露的发布接口（类型擦除 `any` 便于测试替换）。
    let notificationClient: any NotificationClient
    /// 解析远程 payload 并触发路由/本地通知。
    let handleRemoteNotificationUseCase: HandleRemoteNotificationUseCase
    /// 系统推送 token/回调 与用例层的适配。
    let pushAdapter: PushAdapter

    // MARK: - 数据仓库
    //
    // 界面与用例只应依赖这些协议类型，而非具体 `Default*` 类（由容器在 `init` 里装配）。

    /// 当前登录用户资料（会话态，如 Apple 用户标识展示名）。
    let userProfileRepository: any UserProfileRepository
    /// 健康指标时间轴等（远程医疗查询 API）。
    let healthMetricsRepository: any HealthMetricsRepository
    /// 登录、刷新 token、登出。
    let authRepository: any AuthRepository
    /// 本地 AI 偏好（模型、温度等）；与知识库仓库解耦。
    let aiSettingsRepository: any AISettingsRepository
    /// 本地知识库持久化（Core Data：`KnowledgeDocumentEntity` / `KnowledgeChunkEntity`）。
    let knowledgeRepository: any KnowledgeRepository
    /// 本机 GGUF 等小模型加载与推理入口（与云端网关并列供 `AIRuntimeService` 选择）。
    let localModelService: LocalModelService

    // MARK: - 用例（认证、首页、健康、患者、病历草稿、聊天）
    //
    // 按业务域分组；同一域用例共享上游仓库，在 `init` 里按依赖顺序先后构造。

    /// 启动时从 Keychain/会话恢复登录态。
    let restoreSessionUseCase: RestoreSessionUseCase
    /// Sign in with Apple 完整流程。
    let signInWithAppleUseCase: SignInWithAppleUseCase
    /// 清除令牌与会话。
    let signOutUseCase: SignOutUseCase
    /// 首页医疗卡片：成员、病例、体检、用药等摘要（可带远程刷新策略）。
    let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    /// 首页运动与健康（HealthKit）数据。
    let loadHomeMotionHealthUseCase: LoadHomeMotionHealthUseCase
    /// 首页家庭成员增删改选。
    let manageHomeMemberUseCase: ManageHomeMemberUseCase
    /// 请求 HealthKit 读权限（运动健康模块）。
    let requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase
    /// 健康 Tab 时间轴。
    let loadHealthTimelineUseCase: LoadHealthTimelineUseCase
    /// 知识库文档列表（本地 Core Data）。
    let loadKnowledgeListUseCase: LoadKnowledgeListUseCase
    /// 按 ID 加载单篇知识文档正文与元数据。
    let loadKnowledgeDocumentUseCase: LoadKnowledgeDocumentUseCase
    /// 新建空白或导入后的知识文档。
    let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    /// 保存编辑中的标题、正文、标签等。
    let updateKnowledgeDocumentUseCase: UpdateKnowledgeDocumentUseCase
    /// 删除文档及关联切块。
    let deleteKnowledgeDocumentUseCase: DeleteKnowledgeDocumentUseCase
    /// 混合关键词与向量召回的检索（依赖嵌入客户端与 AI 设置中的 endpoint）。
    let searchKnowledgeUseCase: SearchKnowledgeUseCase
    /// 文档变更后重建切块索引（不含向量时可单独调用）。
    let reindexKnowledgeDocumentUseCase: ReindexKnowledgeDocumentUseCase
    /// OpenAI 兼容嵌入 HTTP 客户端（知识切块向量化与语义检索查询向量共用）。
    let knowledgeEmbeddingClient: any KnowledgeEmbeddingClient
    /// 为文档切块批量请求 embedding 并写回仓库。
    let buildKnowledgeEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase
    /// 使用当前选中的对话模型润色选中段落。
    let polishKnowledgeTextUseCase: PolishKnowledgeTextUseCase
    /// 翻译选中段落或全文摘要。
    let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    /// 对知识库内图片附件做 OCR 回填正文。
    let ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase
    /// 从本地文件导入为知识文档。
    let importKnowledgeFromFileUseCase: ImportKnowledgeFromFileUseCase
    /// 从 URL/网页抓取并导入为知识文档。
    let importKnowledgeFromWebUseCase: ImportKnowledgeFromWebUseCase
    /// 聊天侧患者列表（医疗域）。
    let loadPatientsUseCase: LoadPatientsUseCase
    /// 当前选中医患上下文切换。
    let selectPatientUseCase: SelectPatientUseCase
    /// 病历附件先上传文件服务。
    let uploadMedicalDocumentFilesUseCase: UploadMedicalDocumentFilesUseCase
    /// 按类型（检验/处方等）结构化抽取。
    let extractTypedMedicalDocumentUseCase: ExtractTypedMedicalDocumentUseCase
    /// 将结构化结果通过 workflow API 落库。
    let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    /// 将已上传文件 ID 绑定到医疗业务实体。
    let bindUploadedFilesToMedicalBusinessUseCase: BindUploadedFilesToMedicalBusinessUseCase
    /// 拼接患者病历摘要注入聊天 system 上下文。
    let buildPatientContextSummaryUseCase: BuildPatientContextSummaryUseCase
    /// 分页/刷新会话线程列表。
    let loadChatThreadsUseCase: LoadChatThreadsUseCase
    /// 加载某线程下的消息历史（含本地未同步）。
    let loadChatMessagesUseCase: LoadChatMessagesUseCase
    /// 创建新聊天线程。
    let createThreadUseCase: CreateThreadUseCase
    /// 失败气泡重试：重新入同步引擎。
    let retryFailedMessageUseCase: RetryFailedMessageUseCase
    /// 删除线程及其消息（具体是否物理删由仓库实现）。
    let deleteThreadUseCase: DeleteThreadUseCase
    /// 手动或定时拉取远端增量、处理 outbox。
    let syncChatUseCase: SyncChatUseCase
    /// 用户发送一条消息：落库、触发编排（流式模型 + 工具）。
    let sendChatMessageUseCase: SendChatMessageUseCase

    // MARK: - AI 运行时、工具编排、医疗同步、OCR
    //
    // `AIRuntimeStore` 存当前模型、流式状态等；`AIConfigCenter` 合并本地设置与远程配置。
    // `ToolHub` 把草稿确认、知识检索等暴露给聊天工具调用链；`MedicalSyncService` 后台增量同步医疗数据。

    /// 运行时 UI/状态用的大模型选择、生成中等快照。
    let aiRuntimeStore: AIRuntimeStore
    /// 本地 + 远程 AI 配置合并与订阅。
    let aiConfigCenter: AIConfigCenter
    /// 实际调用云端 OpenAI 兼容接口或本机 GGUF。
    let aiRuntimeService: AIRuntimeService
    /// 聊天工具集合（含医疗草稿、知识库写入等）。
    let toolHub: ToolHub
    /// 工具调用审计记录。
    let toolAuditStore: ToolAuditStore
    /// 偏好 + 仓库 + 本地通知的医疗同步调度。
    let medicalSyncService: MedicalSyncService
    /// 阿里云 / 本地 OCR 引擎选择与降级。
    let ocrOrchestrator: OCROrchestrator

    // MARK: - 会话、患者上下文与聊天界面 ViewModel
    //
    // 与 SwiftUI `Scene` 同级常驻：`sessionStore` 管登录态；`patientContextStore` 管当前患者；
    // `chatStateStore` 管线程选中态；三个 ViewModel 供多窗口/多界面共享同一份状态。

    /// 登录态与恢复会话的 Observable 封装。
    let sessionStore: AppSessionStore
    /// 当前选中的医疗成员/患者上下文（首页与聊天共用）。
    let patientContextStore: PatientContextStore
    /// 聊天列表与详情共享的选中线程、输入态等。
    let chatStateStore: ChatStateStore
    /// 知识库列表/搜索/增删改 UI 状态（单例）。
    let knowledgeViewModel: KnowledgeLibraryViewModel
    /// 会话列表 UI（单例）。
    let chatListViewModel: ChatListViewModel
    /// 单会话消息与发送 UI（单例）。
    let chatDetailViewModel: ChatDetailViewModel

    init(
        coreDataStack: CoreDataStack,
        backend: Backend,
        ocrConfiguration: OCRConfiguration = OCRConfiguration(),
        logger: Logger = ConsoleLogger()
    ) {
        // MARK: 基础设施赋值
        // 先完成与后续构造无关的「叶子」依赖，避免在闭包中引用未初始化的 `self`。
        self.coreDataStack = coreDataStack
        self.backend = backend
        self.logger = logger
        self.fileCacheManager = FileCacheManager(logger: logger)
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
        self.fileTransferService = FileTransferService(
            api: backend.files,
            ossAPI: backend.oss,
            ossClient: ossClient,
            ossConfigurationStore: ossConfigurationStore,
            cacheManager: fileCacheManager,
            logger: logger
        )

        // MARK: 仓库层（数据访问抽象）
        // 会话资料与远程健康指标：登录流程中可能触发健康时间轴预拉。
        let profileRepository = SessionBackedUserProfileRepository()
        let healthMetricsRepository = RemoteHealthMetricsRepository(queryAPI: backend.medicalQuery)
        // 认证仓库聚合 Backend + 上述两仓库，负责 token 与登出清理。
        let authRepository = DefaultAuthRepository(
            backend: backend,
            userProfileRepository: profileRepository,
            healthMetricsRepository: healthMetricsRepository,
            logger: logger
        )
        let aiSettingsRepository = DefaultAISettingsRepository(logger: logger)
        // 知识库：独立 Core Data 仓库，不嵌在 AISettings 里，避免提示词仓库与文档仓库概念混淆。
        let knowledgeRepository = CoreDataKnowledgeRepository(coreDataStack: coreDataStack, logger: logger)
        let knowledgeEmbeddingClient = OpenAICompatibleEmbeddingClient()
        let aiRuntimeStore = AIRuntimeStore()
        let localModelService = LocalModelService()
        let remoteConfigProvider = BackendAIRemoteConfigProvider(api: backend.aiConfig)
        let medicalSyncPreferenceRepository = DefaultMedicalSyncPreferenceRepository()
        // 医疗查询：病例、报告、用药等列表/详情（与 workflow 写入 API 分离）。
        let medicalDataRepository = DefaultMedicalDataRepository(
            queryAPI: backend.medicalQuery,
            logger: logger
        )
        // 首页成员：读 medical query + member CRUD API。
        let homeMemberRepository = DefaultHomeMemberRepository(
            medicalQueryAPI: backend.medicalQuery,
            memberAPI: backend.medicalMembers,
            logger: logger
        )
        let homeHealthRepository = HealthKitHomeHealthDataRepository()

        // MARK: AI 配置与运行时网关
        let aiConfigCenter = AIConfigCenter(
            repository: aiSettingsRepository,
            remoteProvider: remoteConfigProvider,
            runtimeStore: aiRuntimeStore,
            logger: logger
        )

        // MARK: OCR 引擎（可选阿里云 / 可选本地 HTTP 服务）
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

        // MARK: 大模型：云端 OpenAI 兼容 + 本机 GGUF，统一由 AIRuntimeService 按配置选型
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

        // MARK: 知识库用例链（列表 → 文档 CRUD → 搜索/重索引 → 向量构建）
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

        // MARK: 患者、病历记录、草稿与「结构化病历上传」流水线
        let patientRepository = DefaultPatientRepository(medicalQueryAPI: backend.medicalQuery)
        let medicalRecordRepository = DefaultMedicalRecordRepository(medicalQueryAPI: backend.medicalQuery)
        let buildPatientContextSummaryUseCase = BuildPatientContextSummaryUseCase(repository: medicalRecordRepository)
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
        let attachmentBinder = DefaultMedicalDocumentAttachmentBinder(
            fileAPI: backend.files,
            logger: logger
        )
        let uploadMedicalDocumentFilesUseCase = UploadMedicalDocumentFilesUseCase(
            fileTransferService: fileTransferService,
            logger: logger
        )
        let extractTypedMedicalDocumentUseCase = ExtractTypedMedicalDocumentUseCase(
            extractor: typedMedicalDocumentExtractor
        )
        let saveTypedMedicalDocumentUseCase = SaveTypedMedicalDocumentUseCase(
            saver: typedMedicalDocumentSaver
        )
        let bindUploadedFilesToMedicalBusinessUseCase = BindUploadedFilesToMedicalBusinessUseCase(
            binder: attachmentBinder
        )

        // MARK: 聊天 Tool 调用：把草稿/知识库/医疗只读查询暴露给模型工具层
        let toolAuditStore = ToolAuditStore()
        let toolHub = ToolHub(
            auditStore: toolAuditStore,
            medicalDataRepository: medicalDataRepository,
            healthMetricsRepository: healthMetricsRepository,
            aiSettingsRepository: aiSettingsRepository,
            searchKnowledgeUseCase: searchKnowledgeUseCase,
            createKnowledgeDocumentUseCase: createKnowledgeDocumentUseCase,
            logger: logger
        )

        // MARK: 聊天持久化与同步（Core Data + Outbox + REST + WebSocket）
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

        // MARK: 应用内通知 + 远程推送
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

        // MARK: 医疗后台同步（可触发本地通知）与 Push 适配
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
        let registerDeviceUseCase = RegisterDeviceUseCase(backend: backend, logger: logger)
        let pushAdapter = PushAdapter(
            handleRemoteNotificationUseCase: handleRemoteNotificationUseCase,
            logger: logger,
            onApnsTokenHex: { hex in
                await registerDeviceUseCase.execute(pushToken: hex, notificationsEnabled: true)
            },
            onRemoteNotificationAuthorizationResolved: { granted in
                if granted {
                    // 同意权限：先标记开启；JSON 省略 push_token 以免覆盖已有行，待 token 回调再写入 hex。
                    await registerDeviceUseCase.execute(pushToken: nil, notificationsEnabled: true)
                } else {
                    // 拒绝或异常：清空服务端 push_token 并标记关闭（与 TrustedDevice 字段语义一致）。
                    await registerDeviceUseCase.execute(pushToken: "", notificationsEnabled: false)
                }
            }
        )

        // MARK: 冷启动编排（不阻塞 UI 的异步任务入口，由 App 生命周期调用）
        let appBootstrapper = AppBootstrapper(
            aiConfigCenter: aiConfigCenter,
            medicalSyncService: medicalSyncService,
            syncChatUseCase: syncChatUseCase,
            routeStore: routeStore,
            ossConfigurationStore: ossConfigurationStore,
            ossAPI: backend.oss,
            registerDevice: { await registerDeviceUseCase.execute() },
            logger: logger
        )

        // MARK: 写回 `self`：仓库与用例（供工厂方法与外部测试/调试访问）
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
        self.uploadMedicalDocumentFilesUseCase = uploadMedicalDocumentFilesUseCase
        self.extractTypedMedicalDocumentUseCase = extractTypedMedicalDocumentUseCase
        self.saveTypedMedicalDocumentUseCase = saveTypedMedicalDocumentUseCase
        self.bindUploadedFilesToMedicalBusinessUseCase = bindUploadedFilesToMedicalBusinessUseCase
        self.buildPatientContextSummaryUseCase = buildPatientContextSummaryUseCase
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.createThreadUseCase = createThreadUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.syncChatUseCase = syncChatUseCase
        self.sendChatMessageUseCase = sendChatMessageUseCase

        self.routeStore = routeStore
        self.registerDeviceUseCase = registerDeviceUseCase
        self.aiRuntimeStore = aiRuntimeStore
        self.aiConfigCenter = aiConfigCenter
        self.aiRuntimeService = aiRuntimeService
        self.toolHub = toolHub
        self.toolAuditStore = toolAuditStore
        self.medicalSyncService = medicalSyncService
        self.ocrOrchestrator = ocrOrchestrator
        self.ossConfigurationStore = ossConfigurationStore
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

        // MARK: 会话 Store 与跨界面共享 ViewModel
        // 注意：`sessionStore` 使用刚赋值的 `restoreSessionUseCase`，`chatListViewModel` 依赖 `sessionStore`，顺序不可颠倒。
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
    ///
    /// 会先 `SparkLogger.configure` 同步全局日志级别与子系统，再构造与 `live` 一致的 `ConsoleLogger`。
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
    ///
    /// 静态懒加载一次，避免每次 Preview 重复冷启动大量依赖；**不得**用于真机生产路径。
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
    //
    // 原则：屏幕只调用 `container.make*ViewModel()`，不直接 `init` 用例链，便于测试时替换容器。
    // 聊天与知识库返回的是上文构造的**共享实例**，以保证导航返回后状态不丢。

    /// 登录页：Apple 登录用例 + 会话 Store。
    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(
            signInWithAppleUseCase: signInWithAppleUseCase,
            sessionStore: sessionStore
        )
    }

    /// 首页：医疗摘要、运动健康、成员管理、HealthKit 授权、患者上下文与通知。
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

    /// 结构化病历上传：先文件上传 → 类型化抽取 → workflow 保存 → 附件绑定。
    func makeMedicalDocumentUploadViewModel() -> MedicalDocumentUploadViewModel {
        MedicalDocumentUploadViewModel(
            patientContextStore: patientContextStore,
            uploadFilesUseCase: uploadMedicalDocumentFilesUseCase,
            extractUseCase: extractTypedMedicalDocumentUseCase,
            saveUseCase: saveTypedMedicalDocumentUseCase,
            bindUseCase: bindUploadedFilesToMedicalBusinessUseCase,
            logger: logger
        )
    }

    /// 健康时间轴 Tab。
    func makeHealthTimelineViewModel() -> HealthTimelineViewModel {
        HealthTimelineViewModel(
            sessionStore: sessionStore,
            loadHealthTimelineUseCase: loadHealthTimelineUseCase
        )
    }

    /// 设置页：登出、医疗后台同步开关/触发等。
    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            sessionStore: sessionStore,
            signOutUseCase: signOutUseCase,
            medicalSyncService: medicalSyncService,
            deviceCache: backend.deviceCache
        )
    }

    /// AI 设置：本地偏好读写 + 可选远程模型列表（`backend.aiConfig`）。
    func makeAISettingsViewModel() -> AISettingsViewModel {
        AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: aiSettingsRepository),
            saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository),
            localModelService: localModelService,
            aiConfigAPI: backend.aiConfig
        )
    }

    /// 向需要单独注入 `ChatStateStore` 的界面暴露同一实例（与列表/详情共享选中态）。
    func makeChatStateStore() -> ChatStateStore {
        chatStateStore
    }

    /// 知识库主列表（共享 `knowledgeViewModel`）。
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

    /// 聊天会话列表（共享 `chatListViewModel`）。
    func makeChatListViewModel() -> ChatListViewModel {
        chatListViewModel
    }

    /// 聊天详情（共享 `chatDetailViewModel`）。
    func makeChatDetailViewModel() -> ChatDetailViewModel {
        chatDetailViewModel
    }
}
