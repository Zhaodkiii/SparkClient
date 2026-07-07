import Foundation

/// 应用的**组合根（Composition Root）**：负责确定 Assembly 装配顺序、持有 facade 与共享运行时。
///
/// ### 设计要点
/// - 使用 `@MainActor` 与 SwiftUI 生命周期对齐，工厂方法创建的 ViewModel 可在主线程安全使用。
/// - **依赖方向**：UI → FeatureFacade / ViewModel → UseCase → Repository / API；具体实现由各领域 Assembly 绑定。
/// - **薄容器原则**：`init` 只组合 `AppAssembly`、`AuthAssembly`、`AIAssembly`、`MedicalAssembly`、`NotificationAssembly`、`ChatAssembly` 的产物。
/// - **单例式 ViewModel**（聊天列表/详情、知识库）：跨界面共享状态，故在 `init` 末尾直接挂到属性上，而不是每次 `make*` 新建。
/// - **预览与生产**：`live()` 读 `AppEnvironment`；`preview` 使用独立子系统与占位 URL，避免污染真机数据。
///
/// ### 初始化顺序（阅读 `init` 时可参考）
/// 1. 基础设施与认证 Assembly。
/// 2. AI 运行时，再装配依赖 AI 的医疗/OCR 与知识库。
/// 3. 通知/路由与聊天 Assembly。
/// 4. 创建 `AppBootstrapper`，再把 Assembly product 写回容器属性。
/// 5. 构造会话 Store 与跨界面共享 ViewModel。
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
    /// 统一存储策略登记表：集中描述各存储后端的作用域、账号隔离与清理策略。
    let storageRegistry: StorageRegistry
    /// 应用版本检查与更新弹窗协调器。
    let versionUpdateCoordinator: AppVersionUpdateCoordinator
    /// 任务中心 UI 观察对象；由 Assembly 封装 `TaskManager.shared` 后注入，View 不再直接访问 singleton。
    let taskManager: TaskManager
    /// 任务同步 facade：根生命周期只依赖协议，不直接触碰 `TaskManager.shared`。
    let taskRuntime: any TaskRuntimeSyncing

    // MARK: - 路由与启动
    //
    // `AppRouteStore`：深链/推送解析后的待处理路由。
    // `AppBootstrapper`：冷启动时拉远程配置、触发医疗同步与聊天同步等。

    /// 待处理导航目标（例如从通知点进某页）。
    let routeStore: AppRouteStore
    /// 通知、深链、登录态和系统生命周期事件的 typed route 消费入口。
    let routeCoordinator: RouteCoordinator
    /// 应用启动阶段副作用（非 UI）的集中入口。
    let appBootstrapper: AppBootstrapper
    /// 设备信息上送聚合协调器（APP-STARTUP-000007）。
    let deviceRegistrationCoordinator: DeviceRegistrationCoordinator
    /// 外部 PDF 打开导入协调器（MEDICAL-IMPORT-000001）。
    let externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    /// 冷启动目标页面公共调度器（APP-COLD-ROUTE-000001）。
    let launchIntentCoordinator: LaunchIntentCoordinator

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
    /// 用药本地提醒同步协调器（MEDICATION-EXECUTION-000002）。
    let medicationReminderSyncCoordinator: MedicationReminderSyncCoordinator

    // MARK: - 数据仓库
    //
    // 界面与用例只应依赖这些协议类型，而非具体 `Default*` 类（由容器在 `init` 里装配）。

    /// 登录、刷新 token、登出。
    let authRepository: any AuthRepository
    /// 账户资料、二次验证与销户提交。
    let accountManagementRepository: any AccountManagementRepository
    /// 本地 AI 偏好（模型、温度等）；与知识库仓库解耦。
    let aiSettingsRepository: any AISettingsRepository
    /// 账号级长期记忆仓储。
    let memoryRepository: any MemoryRepository
    /// 本地知识库持久化（Core Data：`KnowledgeDocumentEntity` / `KnowledgeChunkEntity`）。
    let knowledgeRepository: any KnowledgeRepository
    /// 服务端科普内容仓储：远端文档系统 + JSON 文件缓存。
    let popularScienceRepository: any PopularScienceRepository
    /// 本机 GGUF 等小模型加载与推理入口（与云端网关并列供 `AIRuntimeService` 选择）。
    let localModelService: LocalModelService

    // MARK: - 用例（认证、首页、健康、患者、病历草稿、聊天）
    //
    // 按业务域分组；同一域用例共享上游仓库，在 `init` 里按依赖顺序先后构造。

    /// 启动时从 Keychain/会话恢复登录态。
    let restoreSessionUseCase: RestoreSessionUseCase
    /// Sign in with Apple 完整流程。
    let signInWithAppleUseCase: SignInWithAppleUseCase
    /// 请求手机号验证码。
    let requestPhoneOTPUseCase: RequestPhoneOTPUseCase
    /// 手机号验证码登录。
    let signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase
    /// 清除令牌与会话。
    let signOutUseCase: SignOutUseCase
    /// 加载账户管理页资料。
    let loadAccountProfileUseCase: LoadAccountProfileUseCase
    /// 请求账户高危操作验证。
    let requestAccountVerificationUseCase: RequestAccountVerificationUseCase
    /// 提交账户注销申请。
    let submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase
    /// 首页医疗卡片：成员、病例、体检、用药等摘要（可带远程刷新策略）。
    let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    /// 首页家庭成员增删改选。
    let manageHomeMemberUseCase: ManageHomeMemberUseCase
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
    /// 使用文本优化场景自动生成智能体 system prompt。
    let autoFillAgentPromptUseCase: AutoFillAgentPromptUseCase
    /// 记忆档案读写与召回。
    let loadMemoryArchiveUseCase: LoadMemoryArchiveUseCase
    let saveMemoryUseCase: SaveMemoryUseCase
    let retrieveMemoryUseCase: RetrieveMemoryUseCase
    let updateMemoryUseCase: UpdateMemoryUseCase
    let deleteMemoryUseCase: DeleteMemoryUseCase
    let memoryPreferencesUseCase: MemoryPreferencesUseCase
    /// 对知识库内图片附件做 OCR 回填正文。
    let ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase
    /// 从本地文件导入为知识文档。
    let importKnowledgeFromFileUseCase: ImportKnowledgeFromFileUseCase
    /// 从 URL/网页抓取并导入为知识文档。
    let importKnowledgeFromWebUseCase: ImportKnowledgeFromWebUseCase
    /// 聊天侧成员列表（医疗域）。
    let loadMembersUseCase: LoadMembersUseCase
    /// 当前选中成员切换。
    let selectMemberUseCase: SelectMemberUseCase
    /// 病历附件先上传文件服务。
    let uploadMedicalDocumentFilesUseCase: UploadMedicalDocumentFilesUseCase
    /// 按类型（检验/处方等）结构化抽取。
    let extractTypedMedicalDocumentUseCase: ExtractTypedMedicalDocumentUseCase
    /// 将结构化结果通过 workflow API 落库。
    let saveTypedMedicalDocumentUseCase: SaveTypedMedicalDocumentUseCase
    /// 将已上传文件 ID 绑定到医疗业务实体。
    let bindUploadedFilesToMedicalBusinessUseCase: BindUploadedFilesToMedicalBusinessUseCase
    /// 拼接成员病历摘要注入聊天 system 上下文。
    let buildMemberContextSummaryUseCase: BuildMemberContextSummaryUseCase
    /// 分页/刷新会话线程列表。
    let loadChatThreadsUseCase: LoadChatThreadsUseCase
    /// 加载某线程下的消息历史（含本地未同步）。
    let loadChatMessagesUseCase: LoadChatMessagesUseCase
    /// 聊天读模型（Query 层），与 ``ChatRepository`` 解耦 UI 拼装逻辑。
    let chatQueryService: ChatQueryService
    /// 创建新聊天线程。
    let createThreadUseCase: CreateThreadUseCase
    /// 失败气泡重试：重新入同步引擎。
    let retryFailedMessageUseCase: RetryFailedMessageUseCase
    /// 删除线程及其消息（具体是否物理删由仓库实现）。
    let deleteThreadUseCase: DeleteThreadUseCase
    /// 聊天同步编排（引擎 + 附件管线）。
    let chatSyncSupervisor: ChatSyncSupervisor
    /// 用户发送一条消息：落库、触发编排（流式模型 + 工具）。
    let sendChatMessageUseCase: SendChatMessageUseCase

    // MARK: - AI 运行时、工具编排、医疗同步、OCR
    //
    // `AIRuntimeStore` 存当前模型、流式状态等；`AIConfigCenter` 合并本地设置与远程配置。
    // `ToolHub` 把草稿确认、知识检索等暴露给聊天工具调用链；`MedicalSyncService` 管理同步偏好并预热成员列表缓存。

    /// 运行时 UI/状态用的大模型选择、生成中等快照。
    let aiRuntimeStore: AIRuntimeStore
    /// 本地 + 远程 AI 配置合并与订阅。
    let aiConfigCenter: AIConfigCenter
    /// 实际调用云端 OpenAI 兼容接口或本机 GGUF。
    let aiRuntimeService: AIRuntimeService
    /// 聊天工具集合（含医疗草稿、知识库写入等）。
    let toolHub: ToolHub
    /// 工具调用审计记录。
    let toolInteractionCoordinator: ToolInteractionCoordinator
    /// 偏好 + 仓库 + 本地通知的医疗同步调度。
    let medicalSyncService: MedicalSyncService
    /// 阿里云 / 本地 OCR 引擎选择与降级。
    let ocrOrchestrator: OCROrchestrator

    // MARK: - 会话、成员上下文与聊天界面 ViewModel
    //
    // 与 SwiftUI `Scene` 同级常驻：`sessionStore` 管登录态；`memberContextStore` 管当前成员；
    // `chatStateStore` 管线程选中态；三个 ViewModel 供多窗口/多界面共享同一份状态。

    /// 登录态与恢复会话的 Observable 封装。
    let sessionStore: AppSessionStore
    /// 新用户引导状态：按账号持久化，根协调器只观察这个 Store 做分流。
    let onboardingStore: OnboardingStore
    /// 当前选中的医疗成员上下文（首页与聊天共用）。
    let memberContextStore: MemberContextStore
    /// 聊天列表与详情共享的选中线程、输入态等。
    let chatStateStore: ChatStateStore
    /// 知识库列表/搜索/增删改 UI 状态（单例）。
    let knowledgeViewModel: KnowledgeLibraryViewModel
    /// 科普列表 UI 状态（单例）。
    let popularScienceViewModel: PopularScienceHomeViewModel
    /// 会话列表 UI（单例）。
    let chatListViewModel: ChatListViewModel
    /// 单会话消息与发送 UI（单例）。
    let chatDetailViewModel: ChatDetailViewModel
    /// 账号级运行时重置入口：账号切换、登出、鉴权失效都走这里。
    lazy var accountSessionRuntime: AccountSessionRuntime = {
        AccountSessionRuntime(
            routeCoordinator: routeCoordinator,
            storageRegistry: storageRegistry,
            memberContextStore: memberContextStore,
            chatStateStore: chatStateStore,
            chatListViewModel: chatListViewModel,
            chatSyncSupervisor: chatSyncSupervisor,
            knowledgeViewModel: knowledgeViewModel,
            aiConfigCenter: aiConfigCenter,
            logger: logger,
            clearSessionScopedViewModels: { [weak self] in
                self?.resetSessionScopedViewModels()
            },
            clearExternalMedicalImport: { [weak self] in
                self?.clearExternalMedicalDocumentImport()
            }
        )
    }()

    /// 领域 facade 聚合：UI 层优先消费这里，而不是直接穿透整个 AppContainer。
    lazy var featureFacades: AppFeatureFacades = AppAssembly(
        auth: AuthAssembly(
            sessionStore: sessionStore,
            makeLoginViewModel: { [self] in makeLoginViewModel() },
            logger: logger
        ),
        ai: AIAssembly(
            configCenter: aiConfigCenter,
            runtimeStore: aiRuntimeStore,
            makeSettingsViewModel: { [self] ownerAccountID in
                makeAISettingsViewModel(ownerAccountID: ownerAccountID)
            },
            logger: logger
        ),
        chat: ChatAssembly(
            stateStore: chatStateStore,
            listViewModel: chatListViewModel,
            detailViewModel: chatDetailViewModel,
            syncSupervisor: chatSyncSupervisor,
            logger: logger
        ),
        medical: MedicalAssembly(
            memberContextStore: memberContextStore,
            medicalSyncService: medicalSyncService,
            makeUploadViewModel: { [self] in makeMedicalDocumentUploadViewModel() },
            logger: logger
        ),
        notifications: NotificationAssembly(
            store: notificationStore,
            client: notificationClient,
            pushAdapter: pushAdapter,
            logger: logger
        ),
        onboarding: OnboardingAssembly(
            store: onboardingStore,
            makeFlowViewModel: { [self] in makeOnboardingFlowViewModel() },
            logger: logger
        ),
        mainTab: MainTabAssembly(
            makeDependencies: { [self] ownerAccountID in
                makeMainTabDependencies(ownerAccountID: ownerAccountID)
            },
            logger: logger
        ),
        logger: logger
    ).makeFacade()

    /// 根视图依赖包：App 入口创建后传给 SwiftUI，避免 UI 拿到完整容器。
    lazy var contentDependencies: AppContentDependencies = {
        let lifecycle = AppLifecycleCoordinator(container: self)
        routeCoordinator.bind(lifecycle: lifecycle, sessionStore: sessionStore)
        return AppContentDependencies(
            notificationStore: notificationStore,
            notificationDeliveryCoordinator: notificationDeliveryCoordinator,
            routeCoordinator: routeCoordinator,
            versionUpdateCoordinator: versionUpdateCoordinator,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            coordinator: AppCoordinatorDependencies(
                facades: featureFacades,
                lifecycle: lifecycle,
                versionUpdateCoordinator: versionUpdateCoordinator
            )
        )
    }()

    // MARK: - 会话级缓存 ViewModel（避免网络状态切换时被反复重建）
    private var cachedHomeViewModel: HomeViewModel?
    private var cachedMedicalDocumentUploadViewModel: MedicalDocumentUploadViewModel?
    private var cachedSettingsViewModel: SettingsViewModel?
    private var cachedAccountManagementViewModel: AccountManagementViewModel?
    private var aiSettingsViewModelCache = AccountScopedCache<AISettingsViewModel>()
    private var mainTabDependenciesCache = AccountScopedCache<MainTabDependencies>()

    init(
        coreDataStack: CoreDataStack,
        backend: Backend,
        ocrConfiguration: OCRConfiguration = OCRConfiguration(),
        logger: Logger = ConsoleLogger()
    ) {
        logger.info("AppContainer 开始组合各领域 Assembly", module: .general)
        self.coreDataStack = coreDataStack
        self.backend = backend
        self.logger = logger

        // MARK: 领域 Assembly
        // AppContainer 只决定装配顺序；每个领域内部的真实构造逻辑下沉到对应 Assembly。
        let infrastructure = AppAssembly.makeInfrastructure(backend: backend, logger: logger)
        let auth = AuthAssembly.makeCore(backend: backend, logger: logger)
        let accountManagementRepository = DefaultAccountManagementRepository(backend: backend)
        let ai = AIAssembly.makeCore(
            coreDataStack: coreDataStack,
            backend: backend,
            sessionSnapshotStore: auth.sessionSnapshotStore,
            logger: logger
        )
        let medical = MedicalAssembly.makeCore(
            backend: backend,
            fileTransferService: infrastructure.fileTransferService,
            selectedMemberIDPersistence: auth.selectedMemberIDPersistence,
            aiRuntimeService: ai.aiRuntimeService,
            ocrConfiguration: ocrConfiguration,
            logger: logger
        )
        let knowledge = AIAssembly.makeKnowledge(
            coreDataStack: coreDataStack,
            ai: ai,
            ocrOrchestrator: medical.ocrOrchestrator,
            logger: logger
        )
        let launchIntentCoordinator = LaunchIntentCoordinator(logger: logger)
        let notification = NotificationAssembly.makeCore(
            backend: backend,
            selectedMemberIDPersistence: auth.selectedMemberIDPersistence,
            medicalSyncPreferenceRepository: medical.medicalSyncPreferenceRepository,
            launchIntentCoordinator: launchIntentCoordinator,
            logger: logger
        )
        let chat = ChatAssembly.makeCore(
            coreDataStack: coreDataStack,
            backend: backend,
            infrastructure: infrastructure,
            ai: ai,
            knowledge: knowledge,
            medical: medical,
            logger: logger
        )
        let appBootstrapper = AppAssembly.makeBootstrapper(
            ai: ai,
            notification: notification,
            chat: chat,
            infrastructure: infrastructure,
            backend: backend,
            logger: logger
        )

        // MARK: 写回 `self`：仓库与用例（供工厂方法与外部测试/调试访问）
        self.taskManager = infrastructure.taskManager
        self.taskRuntime = infrastructure.taskRuntime
        self.storageRegistry = infrastructure.storageRegistry
        self.versionUpdateCoordinator = AppVersionUpdateCoordinator(api: backend.version, logger: logger)
        self.fileCacheManager = infrastructure.fileCacheManager
        self.fileTransferService = infrastructure.fileTransferService
        self.ossConfigurationStore = infrastructure.ossConfigurationStore

        self.authRepository = auth.authRepository
        self.accountManagementRepository = accountManagementRepository
        self.restoreSessionUseCase = auth.restoreSessionUseCase
        self.signInWithAppleUseCase = auth.signInWithAppleUseCase
        self.requestPhoneOTPUseCase = auth.requestPhoneOTPUseCase
        self.signInWithPhoneOTPUseCase = auth.signInWithPhoneOTPUseCase
        self.signOutUseCase = auth.signOutUseCase
        self.loadAccountProfileUseCase = LoadAccountProfileUseCase(repository: accountManagementRepository)
        self.requestAccountVerificationUseCase = RequestAccountVerificationUseCase(repository: accountManagementRepository)
        self.submitAccountDeactivationUseCase = SubmitAccountDeactivationUseCase(repository: accountManagementRepository)

        self.aiSettingsRepository = ai.aiSettingsRepository
        self.memoryRepository = ai.memoryRepository
        self.knowledgeEmbeddingClient = ai.knowledgeEmbeddingClient
        self.aiRuntimeStore = ai.aiRuntimeStore
        self.aiConfigCenter = ai.aiConfigCenter
        self.aiRuntimeService = ai.aiRuntimeService
        self.localModelService = ai.localModelService
        self.loadMemoryArchiveUseCase = ai.loadMemoryArchiveUseCase
        self.saveMemoryUseCase = ai.saveMemoryUseCase
        self.retrieveMemoryUseCase = ai.retrieveMemoryUseCase
        self.updateMemoryUseCase = ai.updateMemoryUseCase
        self.deleteMemoryUseCase = ai.deleteMemoryUseCase
        self.memoryPreferencesUseCase = ai.memoryPreferencesUseCase
        self.polishKnowledgeTextUseCase = ai.polishKnowledgeTextUseCase
        self.translateKnowledgeTextUseCase = ai.translateKnowledgeTextUseCase
        self.autoFillAgentPromptUseCase = ai.autoFillAgentPromptUseCase

        self.knowledgeRepository = knowledge.knowledgeRepository
        let popularScienceRepository = RemotePopularScienceRepository(
            api: backend.popularScience,
            cacheStore: PopularScienceCacheStore(),
            logger: logger
        )
        self.popularScienceRepository = popularScienceRepository
        self.loadKnowledgeListUseCase = knowledge.loadKnowledgeListUseCase
        self.loadKnowledgeDocumentUseCase = knowledge.loadKnowledgeDocumentUseCase
        self.createKnowledgeDocumentUseCase = knowledge.createKnowledgeDocumentUseCase
        self.updateKnowledgeDocumentUseCase = knowledge.updateKnowledgeDocumentUseCase
        self.deleteKnowledgeDocumentUseCase = knowledge.deleteKnowledgeDocumentUseCase
        self.searchKnowledgeUseCase = knowledge.searchKnowledgeUseCase
        self.reindexKnowledgeDocumentUseCase = knowledge.reindexKnowledgeDocumentUseCase
        self.buildKnowledgeEmbeddingsUseCase = knowledge.buildKnowledgeEmbeddingsUseCase
        self.ocrKnowledgeImageUseCase = knowledge.ocrKnowledgeImageUseCase
        self.importKnowledgeFromFileUseCase = knowledge.importKnowledgeFromFileUseCase
        self.importKnowledgeFromWebUseCase = knowledge.importKnowledgeFromWebUseCase

        self.loadHomeMedicalOverviewUseCase = medical.loadHomeMedicalOverviewUseCase
        self.manageHomeMemberUseCase = medical.manageHomeMemberUseCase
        self.loadMembersUseCase = medical.loadMembersUseCase
        self.selectMemberUseCase = medical.selectMemberUseCase
        self.uploadMedicalDocumentFilesUseCase = medical.uploadMedicalDocumentFilesUseCase
        self.extractTypedMedicalDocumentUseCase = medical.extractTypedMedicalDocumentUseCase
        self.saveTypedMedicalDocumentUseCase = medical.saveTypedMedicalDocumentUseCase
        self.bindUploadedFilesToMedicalBusinessUseCase = medical.bindUploadedFilesToMedicalBusinessUseCase
        self.buildMemberContextSummaryUseCase = medical.buildMemberContextSummaryUseCase
        self.ocrOrchestrator = medical.ocrOrchestrator

        self.loadChatThreadsUseCase = chat.loadChatThreadsUseCase
        self.loadChatMessagesUseCase = chat.loadChatMessagesUseCase
        self.chatQueryService = chat.chatQueryService
        self.createThreadUseCase = chat.createThreadUseCase
        self.retryFailedMessageUseCase = chat.retryFailedMessageUseCase
        self.deleteThreadUseCase = chat.deleteThreadUseCase
        self.chatSyncSupervisor = chat.chatSyncSupervisor
        self.sendChatMessageUseCase = chat.sendChatMessageUseCase
        self.toolHub = chat.toolHub
//        self.toolAuditStore = chat.toolAuditStore
        self.toolInteractionCoordinator = chat.toolInteractionCoordinator

        self.routeStore = notification.routeStore
        self.routeCoordinator = notification.routeCoordinator
        self.deviceRegistrationCoordinator = notification.deviceRegistrationCoordinator
        self.launchIntentCoordinator = launchIntentCoordinator
        self.externalMedicalDocumentImportCoordinator = ExternalMedicalDocumentImportCoordinator(
            logger: logger,
            launchIntentCoordinator: launchIntentCoordinator
        )
        self.medicalSyncService = notification.medicalSyncService
        self.appBootstrapper = appBootstrapper
        self.notificationStore = notification.notificationStore
        self.notificationMetricsStore = notification.notificationMetricsStore
        self.notificationInboxStore = notification.notificationInboxStore
        self.notificationQueue = notification.notificationQueue
        self.notificationDeliveryCoordinator = notification.notificationDeliveryCoordinator
        self.publishNotificationUseCase = notification.publishNotificationUseCase
        self.notificationClient = notification.notificationClient
        self.handleRemoteNotificationUseCase = notification.handleRemoteNotificationUseCase
        self.pushAdapter = notification.pushAdapter
        self.medicationReminderSyncCoordinator = MedicationReminderSyncCoordinator(
            notificationManager: MedicationReminderNotificationManager(logger: logger),
            permissionCoordinator: MedicationReminderPermissionCoordinator(logger: logger),
            preferencesStore: MedicationReminderPreferencesStore.shared,
            medicalQueryAPI: backend.medicalQuery,
            logger: logger
        )

        // MARK: 会话 Store 与跨界面共享 ViewModel
        // 注意：`sessionStore` 使用刚赋值的 `restoreSessionUseCase`，`chatListViewModel` 依赖 `sessionStore`，顺序不可颠倒。
        self.sessionStore = AppSessionStore(
            restoreSessionUseCase: restoreSessionUseCase,
            sessionSnapshotStore: auth.sessionSnapshotStore
        )
        self.onboardingStore = OnboardingStore(repository: UserDefaultsOnboardingStateRepository())
        self.memberContextStore = notification.memberContextStore
        self.memberContextStore.configure(manage: manageHomeMemberUseCase)
        self.chatStateStore = ChatStateStore()
        self.knowledgeViewModel = KnowledgeLibraryViewModel(
            loadListUseCase: knowledge.loadKnowledgeListUseCase,
            loadDocumentUseCase: knowledge.loadKnowledgeDocumentUseCase,
            createUseCase: knowledge.createKnowledgeDocumentUseCase,
            updateUseCase: knowledge.updateKnowledgeDocumentUseCase,
            deleteUseCase: knowledge.deleteKnowledgeDocumentUseCase,
            searchUseCase: knowledge.searchKnowledgeUseCase,
            reindexUseCase: knowledge.reindexKnowledgeDocumentUseCase
        )
        self.popularScienceViewModel = PopularScienceHomeViewModel(
            loadArticlesUseCase: LoadPopularScienceArticlesUseCase(repository: popularScienceRepository),
            loadCategoriesUseCase: LoadPopularScienceCategoriesUseCase(repository: popularScienceRepository),
            routeStore: routeStore
        )
        self.chatListViewModel = ChatListViewModel(
            stateStore: chatStateStore,
            sessionStore: sessionStore,
            memberContextStore: memberContextStore,
            loadMembersUseCase: medical.loadMembersUseCase,
            selectMemberUseCase: medical.selectMemberUseCase,
            selectedMemberIDPersistence: auth.selectedMemberIDPersistence,
            loadChatThreadsUseCase: chat.loadChatThreadsUseCase,
            loadChatMessagesUseCase: chat.loadChatMessagesUseCase,
            createThreadUseCase: chat.createThreadUseCase,
            deleteThreadUseCase: chat.deleteThreadUseCase,
            updateThreadMetadataUseCase: UpdateChatThreadMetadataUseCase(repository: chat.chatRepository),
            chatSyncSupervisor: chat.chatSyncSupervisor,
            notificationClient: notification.notificationClient
        )
        self.chatDetailViewModel = ChatDetailViewModel(
            stateStore: chatStateStore,
            memberContextStore: memberContextStore,
            chatRepository: chat.chatRepository,
            loadChatThreadsUseCase: chat.loadChatThreadsUseCase,
            loadChatMessagesUseCase: chat.loadChatMessagesUseCase,
            sendMessageUseCase: chat.sendChatMessageUseCase,
            medicalQueryAPI: backend.medicalQuery,
            fileTransferService: infrastructure.fileTransferService,
            ocrOrchestrator: medical.ocrOrchestrator,
            ocrDocumentExtractor: OCRDocumentExtractor(config: ocrConfiguration),
            retryFailedMessageUseCase: chat.retryFailedMessageUseCase,
            updateChatMessageBlocksUseCase: chat.updateChatMessageBlocksUseCase,
            chatSyncSupervisor: chat.chatSyncSupervisor,
            toolInteractionCoordinator: chat.toolInteractionCoordinator,
            notificationClient: notification.notificationClient,
            aiConfigCenter: ai.aiConfigCenter,
            aiSettingsRepository: ai.aiSettingsRepository,
            translateKnowledgeTextUseCase: ai.translateKnowledgeTextUseCase,
            createKnowledgeDocumentUseCase: knowledge.createKnowledgeDocumentUseCase,
            saveTypedMedicalDocumentUseCase: medical.saveTypedMedicalDocumentUseCase,
            logger: logger
        )
        logger.info("AppContainer 组合完成：容器仅持有 Assembly facade 与共享运行时", module: .general)
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
            requestPhoneOTPUseCase: requestPhoneOTPUseCase,
            signInWithPhoneOTPUseCase: signInWithPhoneOTPUseCase,
            sessionStore: sessionStore,
            notificationClient: notificationClient,
            accountSwitchHandler: accountSessionRuntime
        )
    }

    /// 新用户引导：复用账号级 OnboardingStore 与成员上下文，不直接持有完整容器。
    func makeOnboardingFlowViewModel() -> OnboardingFlowViewModel {
        OnboardingFlowViewModel(
            store: onboardingStore,
            memberContextStore: memberContextStore
        )
    }

    /// 首页：医疗摘要、成员管理与成员上下文、通知。
    func makeHomeViewModel() -> HomeViewModel {
        if let cachedHomeViewModel {
            return cachedHomeViewModel
        }
        let created = HomeViewModel(
            sessionStore: sessionStore,
            loadHomeMedicalOverviewUseCase: loadHomeMedicalOverviewUseCase,
            loadMembersUseCase: loadMembersUseCase,
            memberContextStore: memberContextStore,
            memberModuleSetupUseCase: MemberModuleSetupUseCase(
                medicalQueryAPI: backend.medicalQuery,
                logger: logger
            ),
            shareMemberUseCase: ShareMemberUseCase(memberAPI: backend.medicalMembers),
            memberInviteUseCase: MemberInviteUseCase(memberAPI: backend.medicalMembers),
            manageMemberBindingUseCase: ManageMemberBindingUseCase(memberAPI: backend.medicalMembers),
            notificationClient: notificationClient,
            logger: logger
        )
        cachedHomeViewModel = created
        return created
    }

    /// 结构化病历上传：先文件上传 → 类型化抽取 → workflow 保存 → 附件绑定。
    func makeMedicalDocumentUploadViewModel() -> MedicalDocumentUploadViewModel {
        if let cachedMedicalDocumentUploadViewModel {
            return cachedMedicalDocumentUploadViewModel
        }
        let created = MedicalDocumentUploadViewModel(
            memberContextStore: memberContextStore,
            uploadFilesUseCase: uploadMedicalDocumentFilesUseCase,
            extractUseCase: extractTypedMedicalDocumentUseCase,
            saveUseCase: saveTypedMedicalDocumentUseCase,
            bindUseCase: bindUploadedFilesToMedicalBusinessUseCase,
            aiConfigCenter: aiConfigCenter,
            workflowAPIForLocalForms: backend.medicalWorkflow,
            notificationClient: notificationClient,
            pushAdapter: pushAdapter,
            logger: logger
        )
        cachedMedicalDocumentUploadViewModel = created
        return created
    }

    /// 成员引导/详情等嵌套流程专用：每次创建独立实例，不与首页 Tab 上传 VM 共用缓存。
    func makeScopedMedicalDocumentUploadViewModel() -> MedicalDocumentUploadViewModel {
        MedicalDocumentUploadViewModel(
            memberContextStore: memberContextStore,
            uploadFilesUseCase: uploadMedicalDocumentFilesUseCase,
            extractUseCase: extractTypedMedicalDocumentUseCase,
            saveUseCase: saveTypedMedicalDocumentUseCase,
            bindUseCase: bindUploadedFilesToMedicalBusinessUseCase,
            aiConfigCenter: aiConfigCenter,
            workflowAPIForLocalForms: backend.medicalWorkflow,
            notificationClient: notificationClient,
            pushAdapter: pushAdapter,
            logger: logger
        )
    }

    /// 设置页：登出、医疗后台同步开关/触发等。
    func makeSettingsViewModel() -> SettingsViewModel {
        if let cachedSettingsViewModel {
            return cachedSettingsViewModel
        }
        let created = SettingsViewModel(
            medicalSyncService: medicalSyncService,
            deviceCache: backend.deviceCache
        )
        cachedSettingsViewModel = created
        return created
    }

    /// 账户管理：账户资料、退出登录、注销验证与最终提交。
    func makeAccountManagementViewModel() -> AccountManagementViewModel {
        if let cachedAccountManagementViewModel {
            return cachedAccountManagementViewModel
        }
        let created = AccountManagementViewModel(
            loadAccountProfileUseCase: loadAccountProfileUseCase,
            requestAccountVerificationUseCase: requestAccountVerificationUseCase,
            submitAccountDeactivationUseCase: submitAccountDeactivationUseCase,
            signOutUseCase: signOutUseCase,
            sessionStore: sessionStore,
            memberContextStore: memberContextStore
        )
        cachedAccountManagementViewModel = created
        return created
    }

    /// 用户会话结束时，清理与会话绑定的 ViewModel，避免下次登录复用旧界面状态。
    func resetSessionScopedViewModels() {
        cachedHomeViewModel = nil
        cachedMedicalDocumentUploadViewModel = nil
        cachedSettingsViewModel = nil
        cachedAccountManagementViewModel = nil
        aiSettingsViewModelCache.clear()
        mainTabDependenciesCache.clear()
        logger.info("账号级 ViewModel 与主 Tab 依赖缓存已清理", module: .general)
    }

    func clearExternalMedicalDocumentImport() {
        externalMedicalDocumentImportCoordinator.clearAll()
        launchIntentCoordinator.discardAll(reason: "account_changed")
        launchIntentCoordinator.updateReadiness { $0 = LaunchIntentReadiness() }
        Task {
            if case .signedIn(let session) = sessionStore.state {
                await medicationReminderSyncCoordinator.clearAllForAccount(session.accountID)
            }
            medicationReminderSyncCoordinator.deactivate()
        }
        logger.info("外部医疗 PDF 导入与冷启动 intent 已清理", module: .medical)
    }

    /// 主 Tab 依赖包：同一账号会话期间只创建一次。
    ///
    /// 这里是防止网络抖动、前后台切换、SwiftUI body 重算导致首页/聊天/设置缓存重建的关键边界。
    /// 只有 `AccountSessionRuntime` 在明确登出或切换账号时才会清掉这组缓存。
    func makeMainTabDependencies(ownerAccountID: Int64) -> MainTabDependencies {
        if mainTabDependenciesCache.matches(ownerAccountID),
           let cached = mainTabDependenciesCache.value {
            logger.debug("主 Tab 依赖命中账号级缓存 accountID=\(ownerAccountID)", module: .general)
            return cached
        }

        logger.info("主 Tab 依赖首次初始化 accountID=\(ownerAccountID)", module: .general)
        let aiSettingsViewModel = makeAISettingsViewModel(ownerAccountID: ownerAccountID)
        let homeViewModel = makeHomeViewModel()
        let medicalDocumentUploadViewModel = makeMedicalDocumentUploadViewModel()
        let memberFlowMedicalDocumentUploadViewModel = makeScopedMedicalDocumentUploadViewModel()
        let homeLaunchIntentConsumer = HomeLaunchIntentConsumer(
            coordinator: launchIntentCoordinator,
            routeStore: routeStore,
            uploadViewModel: medicalDocumentUploadViewModel,
            homeViewModel: homeViewModel,
            sessionStore: sessionStore,
            logger: logger
        )
        let medicationReminderOwnershipCoordinator = MedicationReminderOwnershipCoordinator(
            medicalQueryAPI: backend.medicalQuery,
            syncCoordinator: medicationReminderSyncCoordinator,
            notificationClient: notificationClient,
            logger: logger
        )
        let created = MainTabDependencies(
            scope: .accountScoped,
            routeStore: routeStore,
            homeDependencies: HomeFeatureDependencies(
                medicalWorkflowAPI: backend.medicalWorkflow,
                medicalQueryAPI: backend.medicalQuery,
                medicalMemberAPI: backend.medicalMembers,
                memberModuleSetupUseCase: MemberModuleSetupUseCase(
                    medicalQueryAPI: backend.medicalQuery,
                    logger: logger
                ),
                shareMemberUseCase: ShareMemberUseCase(memberAPI: backend.medicalMembers),
                memberInviteUseCase: MemberInviteUseCase(memberAPI: backend.medicalMembers),
                manageMemberBindingUseCase: ManageMemberBindingUseCase(memberAPI: backend.medicalMembers),
                fileTransferService: fileTransferService,
                taskManager: taskManager,
                logger: logger,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                memberFlowMedicalDocumentUploadViewModel: memberFlowMedicalDocumentUploadViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                routeStore: routeStore,
                sessionStore: sessionStore,
                medicationReminderSyncCoordinator: medicationReminderSyncCoordinator,
                medicationReminderOwnershipCoordinator: medicationReminderOwnershipCoordinator,
                nutritionDependencies: HomeFeatureDependencies.makeNutritionDependencies(
                    backend: backend,
                    memberContextStore: memberContextStore,
                    aiRuntimeService: aiRuntimeService,
                    configCenter: aiConfigCenter,
                    notificationStore: notificationStore,
                    logger: logger
                ),
                launchIntentCoordinator: launchIntentCoordinator,
                homeLaunchIntentConsumer: homeLaunchIntentConsumer
            ),
            knowledgeDependencies: KnowledgeFeatureDependencies(
                makeEditorViewModel: { [self] documentID in
                    makeKnowledgeDocumentEditorViewModel(documentID: documentID)
                }
            ),
            popularScienceDependencies: PopularScienceFeatureDependencies(
                makeDetailViewModel: { [self] articleID in
                    makePopularScienceArticleDetailViewModel(articleID: articleID)
                }
            ),
            taskManager: taskManager,
            homeViewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            knowledgeViewModel: makeKnowledgeLibraryViewModel(),
            popularScienceViewModel: makePopularScienceHomeViewModel(),
            chatStateStore: chatStateStore,
            chatListViewModel: chatListViewModel,
            chatDetailViewModel: chatDetailViewModel,
            settingsViewModel: makeSettingsViewModel(),
            accountManagementViewModel: makeAccountManagementViewModel(),
            aiSettingsViewModel: aiSettingsViewModel,
            versionUpdateCoordinator: versionUpdateCoordinator,
            memberContextStore: memberContextStore,
            pushAdapter: pushAdapter,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: launchIntentCoordinator
        )
        mainTabDependenciesCache.store(created, ownerAccountID: ownerAccountID)
        return created
    }

    /// AI 设置：本地偏好读写 + 可选远程模型列表（`backend.aiConfig`）。
    func makeAISettingsViewModel(ownerAccountID: Int64) -> AISettingsViewModel {
        if aiSettingsViewModelCache.matches(ownerAccountID),
           let cached = aiSettingsViewModelCache.value {
            return cached
        }

        let autoFillAgentPromptUseCase = self.autoFillAgentPromptUseCase
        let translateKnowledgeTextUseCase = self.translateKnowledgeTextUseCase
        let ocrKnowledgeImageUseCase = self.ocrKnowledgeImageUseCase
        let created = AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: aiSettingsRepository),
            saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository),
            localModelService: localModelService,
            ownerAccountIDForLoad: ownerAccountID,
            aiConfigAPI: backend.aiConfig,
            aiConfigCenter: aiConfigCenter,
            pushAdapter: pushAdapter,
            promptTooling: DefaultAISettingsPromptTooling(
                autoFillAgentPromptUseCase: autoFillAgentPromptUseCase,
                translateKnowledgeTextUseCase: translateKnowledgeTextUseCase,
                ocrKnowledgeImageUseCase: ocrKnowledgeImageUseCase
            ),
            memoryTooling: AISettingsMemoryTooling(
                loadMemoryArchiveUseCase: loadMemoryArchiveUseCase,
                saveMemoryUseCase: saveMemoryUseCase,
                updateMemoryUseCase: updateMemoryUseCase,
                deleteMemoryUseCase: deleteMemoryUseCase,
                memoryPreferencesUseCase: memoryPreferencesUseCase
            )
        )
        aiSettingsViewModelCache.store(created, ownerAccountID: ownerAccountID)
        return created
    }

    /// 向需要单独注入 `ChatStateStore` 的界面暴露同一实例（与列表/详情共享选中态）。
    func makeChatStateStore() -> ChatStateStore {
        chatStateStore
    }

    /// 知识库主列表（共享 `knowledgeViewModel`）。
    func makeKnowledgeLibraryViewModel() -> KnowledgeLibraryViewModel {
        knowledgeViewModel
    }

    /// 科普主列表（共享 `popularScienceViewModel`）。
    func makePopularScienceHomeViewModel() -> PopularScienceHomeViewModel {
        popularScienceViewModel
    }

    /// 科普详情页 ViewModel（按文章 ID 创建，详情页持有自己的阅读计时生命周期）。
    func makePopularScienceArticleDetailViewModel(articleID: Int) -> PopularScienceArticleDetailViewModel {
        PopularScienceArticleDetailViewModel(
            articleID: articleID,
            loadDetailUseCase: LoadPopularScienceArticleDetailUseCase(repository: popularScienceRepository),
            reportReadingUseCase: ReportPopularScienceReadingUseCase(repository: popularScienceRepository)
        )
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
            aiConfigCenter: aiConfigCenter,
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

    /// 服务端明确返回鉴权失效时触发：
    /// 清理本地会话与 token，并切回登录态。
    func forceSignOutAfterServerAuthInvalidation(invalidationMessage: String = "") async {
        logger.warning("检测到服务端明确鉴权失效，准备强制回到登录页。", module: .auth)
        if case .signedIn(let session) = sessionStore.state {
            await medicationReminderSyncCoordinator.clearAllForAccount(session.accountID)
            medicationReminderSyncCoordinator.deactivate()
        }
        do {
            try await signOutUseCase.execute()
        } catch {
            logger.warning("强制登出执行失败，继续回收本地会话状态：\(error.localizedDescription)", module: .auth)
        }
        await accountSessionRuntime.clearSessionPersistenceAndActivateGuest()
        publishAuthInvalidationBanner(for: invalidationMessage)
    }

    func publishAuthInvalidationBanner(for invalidationMessage: String) {
        let normalized = invalidationMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let localizationKey: String
        switch normalized {
        case "device_session_revoked", "device_session_replaced":
            localizationKey = "auth.session.device_replaced"
        case "device_mismatch":
            localizationKey = "auth.session.device_mismatch"
        case "device_session_not_found":
            localizationKey = "auth.session.device_not_found"
        case "token_not_valid":
            localizationKey = "api_error.msg.token_not_valid"
        default:
            if normalized.isEmpty {
                return
            }
            localizationKey = "api_error.msg.\(normalized.replacingOccurrences(of: " ", with: "_"))"
        }
        notificationClient.warning(
            L10n.text(localizationKey, fallback: L10n.text("api_error.msg.token_not_valid")),
            source: "auth.session"
        )
    }
}
