import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    let chatRepository: any ChatRepository
    let auditStore: ToolAuditStore
    let medicalQueryAPI: SparkMedicalQueryAPI
    let aiSettingsRepository: any AISettingsRepository
    let aiConfigCenter: AIConfigCenter
    let runtimeService: any AIRuntimeServing
    let taskService: TaskService
    let saveMemoryUseCase: SaveMemoryUseCase
    let retrieveMemoryUseCase: RetrieveMemoryUseCase
    let updateMemoryUseCase: UpdateMemoryUseCase
    let memoryPreferencesUseCase: MemoryPreferencesUseCase
    /// 知识库检索/创建：经用例访问 `CoreDataKnowledgeRepository`，避免在此直接操作持久化。
    let searchKnowledgeUseCase: SearchKnowledgeUseCase
    let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    /// 与上传流水线共用：对话工具 `generate_structured_health_card` 的结构化抽取。
    let typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor
    /// 工具异步任务向助手消息落库 UI 副作用（经 `MessageRunActor` 串行写入）。
    let sideEffectSink: any ChatSideEffectSink
    let healthTool: SparkHealthTool
    let toolInteractionCoordinator: ToolInteractionCoordinator?
    let healthResourceToolService: any HealthResourceToolService
    let toolModelEgressConsentPolicy: ToolModelEgressConsentPolicy
    let webSearchGateway: WebSearchGateway
    let weatherGateway: WeatherGateway
    let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    var canvasStore: [String: String] = [:]

    init(
        chatRepository: any ChatRepository,
        auditStore: ToolAuditStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        aiSettingsRepository: any AISettingsRepository,
        aiConfigCenter: AIConfigCenter,
        runtimeService: any AIRuntimeServing,
        taskService: TaskService,
        saveMemoryUseCase: SaveMemoryUseCase,
        retrieveMemoryUseCase: RetrieveMemoryUseCase,
        updateMemoryUseCase: UpdateMemoryUseCase,
        memoryPreferencesUseCase: MemoryPreferencesUseCase,
        searchKnowledgeUseCase: SearchKnowledgeUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor,
        sideEffectSink: any ChatSideEffectSink,
        healthTool: SparkHealthTool = .shared,
        toolInteractionCoordinator: ToolInteractionCoordinator? = nil,
        healthResourceToolService: (any HealthResourceToolService)? = nil,
        toolModelEgressConsentPolicy: ToolModelEgressConsentPolicy = ToolModelEgressConsentPolicy(),
        webSearchGateway: WebSearchGateway = WebSearchGateway(),
        weatherGateway: WeatherGateway = WeatherGateway(),
        logger: Logger = ConsoleLogger()
    ) {
        self.chatRepository = chatRepository
        self.auditStore = auditStore
        self.medicalQueryAPI = medicalQueryAPI
        self.aiSettingsRepository = aiSettingsRepository
        self.aiConfigCenter = aiConfigCenter
        self.runtimeService = runtimeService
        self.taskService = taskService
        self.saveMemoryUseCase = saveMemoryUseCase
        self.retrieveMemoryUseCase = retrieveMemoryUseCase
        self.updateMemoryUseCase = updateMemoryUseCase
        self.memoryPreferencesUseCase = memoryPreferencesUseCase
        self.searchKnowledgeUseCase = searchKnowledgeUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.typedMedicalDocumentExtractor = typedMedicalDocumentExtractor
        self.sideEffectSink = sideEffectSink
        self.healthTool = healthTool
        self.toolInteractionCoordinator = toolInteractionCoordinator
        self.healthResourceToolService = healthResourceToolService
            ?? DefaultHealthResourceToolService(medicalQueryAPI: medicalQueryAPI)
        self.toolModelEgressConsentPolicy = toolModelEgressConsentPolicy
        self.webSearchGateway = webSearchGateway
        self.weatherGateway = weatherGateway
        self.logger = logger
    }

    func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    func shortConversationID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }
}
