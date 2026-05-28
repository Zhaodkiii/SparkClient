import Foundation

/// AI 配置来源。
/// - localDefault: 兼容旧日志名；新解析链优先使用 `localCatalog` / `proOverlay`。
/// - localCatalog: 用户本地目录（system/custom/LOCAL）合成的配置。
/// - proOverlay: 后端 Pro bootstrap overlay 下发的配置。
/// - runtimeOverride: 运行期覆盖（如动态实验、调试开关或远端热更新映射后的本地覆盖）。
/// - trialPolicy: 试用策略下发的配置（例如限时试用期间指定的模型与参数）。
enum AIConfigSource: String, Codable, Sendable {
    case localDefault
    case localCatalog
    case proOverlay
    case userOverride
    case runtimeOverride
    case trialPolicy
}

enum AIProviderAPIStyle: String, Codable, Sendable {
    case openAICompatible
    case localGGUF
}

struct AIProviderAdapter: Equatable, Sendable {
    let providerID: String
    let displayName: String
    let apiStyle: AIProviderAPIStyle

    var isLocal: Bool {
        apiStyle == .localGGUF
    }
}

enum AIProviderAdapterRegistry {
    static func adapter(for providerID: String) -> AIProviderAdapter {
        let normalized = AIProviderIdentifier.normalize(providerID)
        if normalized == LocalModelService.localProviderID {
            return AIProviderAdapter(providerID: normalized, displayName: LocalModelService.localCompany, apiStyle: .localGGUF)
        }
        return AIProviderAdapter(providerID: normalized, displayName: normalized, apiStyle: .openAICompatible)
    }
}

/// 单个场景下“可序列化/可存储”的原始配置快照。
/// 该结构用于承载字符串型 endpoint，并在使用前转为 `AIResolvedConfig`。
struct AIScenarioConfig: Codable, Equatable, Sendable {
    /// 接口地址字符串（尚未校验为 `URL`）。
    var endpoint: String
    /// 模型名（通常与服务端可识别模型标识一致）。
    var model: String
    /// 可选 API Key；为空表示走统一鉴权或由服务端代理鉴权。
    var apiKey: String?
    /// 采样温度，越高随机性越强，越低越稳定。
    var temperature: Double
    /// 单次生成可用的最大 token 上限。
    var maxTokens: Int

    /// 构造场景配置。
    /// 默认参数适合保守稳定策略：低温度 + 中等 token 上限。
    init(
        endpoint: String,
        model: String,
        apiKey: String? = nil,
        temperature: Double = 0.2,
        maxTokens: Int
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    /// 将原始配置解析为运行态可用配置：
    /// 1) 校验 `endpoint` 是否能构造 URL 且包含 scheme；
    /// 2) 挂载来源 `source`，便于后续审计和调试；
    /// 3) 失败时抛出 `AIConfigError.invalidEndpoint`。
    func toResolvedConfig(source: AIConfigSource) throws -> AIResolvedConfig {
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw AIConfigError.invalidEndpoint(endpoint)
        }
        return AIResolvedConfig(
            endpoint: url,
            model: model,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens,
            source: source
        )
    }
}

/// 运行时已解析配置。
/// 与 `AIScenarioConfig` 区别：
/// - endpoint 从 `String` 提升为已校验 `URL`；
/// - 额外携带 `source` 记录配置来源。
struct AIResolvedConfig: Equatable, Sendable {
    /// 已校验的请求地址。
    let endpoint: URL
    /// 选定模型标识。
    let model: String
    /// 可选 API Key。
    let apiKey: String?
    /// 采样温度。
    let temperature: Double
    /// 最大 token 上限。
    let maxTokens: Int
    /// 配置来源（默认值/运行时覆盖/试用策略）。
    let source: AIConfigSource
}

/// AI 配置域错误定义。
enum AIConfigError: LocalizedError {
    /// endpoint 非法（URL 无法构建或缺少 scheme）。
    case invalidEndpoint(String)
    /// 请求了未配置的场景。
    case missingScenario(AIScenario)
    /// 场景下没有可用模型行。
    case missingModelForScenario(AIScenario)
    /// 运行时缓存尚未完成本地构建（未登录或未 bootstrap）。
    case runtimeNotBootstrapped

    /// 面向日志与上层展示的错误描述。
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "AI 服务地址非法：\(endpoint)"
        case .missingScenario(let scenario):
            return "未找到场景「\(scenario.rawValue)」对应的 AI 配置"
        case .missingModelForScenario(let scenario):
            return "场景「\(scenario.rawValue)」暂无可用的 AI 模型"
        case .runtimeNotBootstrapped:
            return "AI 运行环境未初始化完成，请稍后重试"
        }
    }
}

/// 试用态信息快照。
/// 用于表达“当前用户是否在 AI 试用窗口内”及剩余时长等信息。
struct AITrialState: Codable, Equatable, Sendable {
    /// 试用状态标识（如 none/active/expired，具体由服务端约定）。
    var status: String
    /// 是否当前有效。
    var isActive: Bool
    /// 授权来源（如 auto/manual/campaign 等）。
    var grantSource: String
    /// 试用开始时间。
    var startedAt: Date?
    /// 试用过期时间。
    var expiresAt: Date?
    /// 剩余秒数（便于客户端倒计时显示）。
    var remainingSeconds: Int

    /// 非激活默认态，作为本地兜底初始值。
    static let inactive = AITrialState(
        status: "none",
        isActive: false,
        grantSource: "auto",
        startedAt: nil,
        expiresAt: nil,
        remainingSeconds: 0
    )
}

/// 试用申请提交结果（`/api/v1/ai/trial/apply/`）。
struct AITrialApplicationSubmission: Codable, Equatable, Sendable {
    var submitted: Bool
    var applicationId: Int
    var sequence: Int
    var status: String
    var message: String
}

/// 试用策略中“场景 -> 模型配置”的一条映射记录。
struct AITrialModelPolicyItem: Codable, Equatable, Sendable {
    /// 目标场景。
    var scenario: AIScenario
    /// 该场景对应配置。
    var config: AIScenarioConfig
    /// 对应服务端 `is_default`；当同一场景有多条模型配置时，应仅有一条为 true。
    var isDefault: Bool

    init(scenario: AIScenario, config: AIScenarioConfig, isDefault: Bool = false) {
        self.scenario = scenario
        self.config = config
        self.isDefault = isDefault
    }


    /// 自定义解码：
    /// - 兼容历史数据中缺失 `isDefault` 的情况，默认回退为 `false`。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        scenario = try c.decode(AIScenario.self, forKey: .key("scenario"))
        config = try c.decode(AIScenarioConfig.self, forKey: .key("config"))
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .key("isDefault")) ?? false
    }

    /// 自定义编码：显式输出全部字段，避免策略透传时语义丢失。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(scenario, forKey: .key("scenario"))
        try c.encode(config, forKey: .key("config"))
        try c.encode(isDefault, forKey: .key("isDefault"))
    }
}

// MARK: - 多模型场景启动配置（对应 `/api/v1/ai/config/bootstrap/` 的 `scenarios` 对象）

/// 场景下的一条模型配置（由 bootstrap 的 `default_model` 与 `models[]` 组成）。
struct AIScenarioRemoteModelRow: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var displayName: String
    var identity: String
    var providerID: String
    var company: String
    var endpoint: String
    var apiKey: String?
    var supportsSearch: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportsToolUse: Bool
    var supportsVoiceGen: Bool
    var supportsImageGen: Bool
    var supportsText: Bool
    var supportsDeepReasoning: Bool
    var reasoningControllable: Bool
    var priceTier: Int
    var systemProvision: String?
    var icon: String?
    var briefDescription: String?
    var source: String
    var aiScenarios: [String]
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var isDefault: Bool = false
    var temperature: Double
    var maxTokens: Int
    var baseModelName: String?
    var localFilename: String?

    var id: String {
        name
    }

    var model: String {
        get { name }
        set { name = newValue }
    }

    var providerCompany: String? {
        company.isEmpty ? nil : company
    }

    var displayTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    var composerIconSystemName: String {
        let trimmed = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false {
            return trimmed
        }
        return identity == AIModelIdentity.agent.rawValue ? "person.crop.circle" : "cpu"
    }

    var systemPrompt: String? {
        guard let trimmed = systemProvision?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }


    func asScenarioConfig() -> AIScenarioConfig {
        AIScenarioConfig(
            endpoint: endpoint,
            model: name,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    init(
        name: String,
        displayName: String,
        identity: String,
        providerID: String? = nil,
        company: String,
        endpoint: String,
        apiKey: String?,
        supportsSearch: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportsToolUse: Bool,
        supportsVoiceGen: Bool,
        supportsImageGen: Bool,
        supportsText: Bool,
        supportsDeepReasoning: Bool,
        reasoningControllable: Bool,
        priceTier: Int,
        systemProvision: String?,
        icon: String?,
        briefDescription: String?,
        source: String,
        aiScenarios: [String],
        aiToolScenarios: [String],
        relatedTaskCodes: [String] = [],
        isDefault: Bool = false,
        temperature: Double = 0.2,
        maxTokens: Int,
        baseModelName: String? = nil,
        localFilename: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.company = company
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.supportsSearch = supportsSearch
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportsToolUse = supportsToolUse
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsImageGen = supportsImageGen
        self.supportsText = supportsText
        self.supportsDeepReasoning = supportsDeepReasoning
        self.reasoningControllable = reasoningControllable
        self.priceTier = priceTier
        self.systemProvision = systemProvision
        self.icon = icon
        self.briefDescription = briefDescription
        self.source = source
        self.aiScenarios = aiScenarios
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.isDefault = isDefault
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.baseModelName = baseModelName
        self.localFilename = localFilename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        name = try c.decode(String.self, forKey: .key("name"))
        displayName = try c.decode(String.self, forKey: .key("displayName"))
        identity = try c.decode(String.self, forKey: .key("identity"))
        company = try c.decode(String.self, forKey: .key("company"))
        providerID = AIProviderIdentifier.normalize(try c.decodeIfPresent(String.self, forKey: .key("providerId")) ?? company)
        endpoint = try c.decode(String.self, forKey: .key("endpoint"))
        apiKey = try c.decodeIfPresent(String.self, forKey: .key("apiKey"))
        supportsSearch = try c.decode(Bool.self, forKey: .key("supportsSearch"))
        supportsMultimodal = try c.decode(Bool.self, forKey: .key("supportsMultimodal"))
        supportsReasoning = try c.decode(Bool.self, forKey: .key("supportsReasoning"))
        supportsToolUse = try c.decode(Bool.self, forKey: .key("supportsToolUse"))
        supportsVoiceGen = try c.decode(Bool.self, forKey: .key("supportsVoiceGen"))
        supportsImageGen = try c.decode(Bool.self, forKey: .key("supportsImageGen"))
        supportsText = try c.decode(Bool.self, forKey: .key("supportsText"))
        supportsDeepReasoning = try c.decode(Bool.self, forKey: .key("supportsDeepReasoning"))
        reasoningControllable = try c.decode(Bool.self, forKey: .key("reasoningControllable"))
        priceTier = try c.decode(Int.self, forKey: .key("priceTier"))
        systemProvision = try c.decodeIfPresent(String.self, forKey: .key("systemProvision"))
        icon = try c.decodeIfPresent(String.self, forKey: .key("icon"))
        briefDescription = try c.decodeIfPresent(String.self, forKey: .key("briefDescription"))
        source = try c.decode(String.self, forKey: .key("source"))
        aiScenarios = try c.decodeIfPresent([String].self, forKey: .key("aiScenarios")) ?? []
        aiToolScenarios = try c.decodeIfPresent([String].self, forKey: .key("aiToolScenarios")) ?? []
        relatedTaskCodes = try c.decodeIfPresent([String].self, forKey: .key("relatedTaskCodes")) ?? []
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .key("isDefault")) ?? false
        temperature = try c.decode(Double.self, forKey: .key("temperature"))
        maxTokens = try c.decode(Int.self, forKey: .key("maxTokens"))
        baseModelName = try c.decodeIfPresent(String.self, forKey: .key("baseModelName"))
        localFilename = try c.decodeIfPresent(String.self, forKey: .key("localFilename"))
    }

    var configSource: AIConfigSource {
        switch AIRecordSource(rawValue: source) {
        case .pro:
            return .proOverlay
        case .system, .custom:
            return .localCatalog
        case .none:
            return .localDefault
        }
    }
}

/// 单个场景的远端模型集合（包含默认模型名与候选模型列表）。
struct AIScenarioRemoteBundle: Codable, Equatable, Sendable {
    /// 场景下默认模型名称。
    var defaultModelName: String
    /// 候选模型行列表。
    var models: [AIScenarioRemoteModelRow]


    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        let models = try c.decode([AIScenarioRemoteModelRow].self, forKey: .key("models"))
        let decodedDefault = try c.decodeIfPresent(String.self, forKey: .key("defaultModel"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModelName: String = {
            if let decodedDefault, decodedDefault.isEmpty == false,
               models.contains(where: { $0.name == decodedDefault })
            {
                return decodedDefault
            }
            if let row = models.first(where: { $0.isDefault }) {
                return row.name
            }
            return models.first?.name ?? ""
        }()
        self.defaultModelName = defaultModelName
        self.models = models.map { row in
            var m = row
            m.isDefault = m.name == defaultModelName
            return m
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(defaultModelName, forKey: .key("defaultModel"))
        try c.encode(models, forKey: .key("models"))
    }

    init(defaultModelName: String, models: [AIScenarioRemoteModelRow]) {
        self.defaultModelName = defaultModelName
        self.models = models
    }

    /// 用单模型配置构造“多模型格式”兜底包。
    /// 使用场景：
    /// - 老数据仅有单模型配置；
    /// - 远端多模型 bootstrap 尚不可用时，统一走同一解析链路。
    static func singleModelFallback(_ config: AIScenarioConfig) -> AIScenarioRemoteBundle {
        let row = AIScenarioRemoteModelRow(
            name: config.model,
            displayName: config.model,
            identity: "model",
            providerID: "SPARK",
            company: "SPARK",
            endpoint: config.endpoint,
            apiKey: config.apiKey,
            supportsSearch: true,
            supportsMultimodal: true,
            supportsReasoning: true,
            supportsToolUse: true,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: true,
            reasoningControllable: false,
            priceTier: 0,
            systemProvision: nil,
            icon: nil,
            briefDescription: nil,
            source: AIRecordSource.system.rawValue,
            aiScenarios: [],
            aiToolScenarios: [],
            isDefault: true,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )
        return AIScenarioRemoteBundle(defaultModelName: config.model, models: [row])
    }

    /// 解析最终选中模型行，优先级：
    /// 1) 若传入 `preferredModelName` 且命中，优先返回；
    /// 2) 否则返回 `isDefault == true` 的行；
    /// 3) 再否则返回第一行；
    /// 4) 若 `models` 为空则返回 `nil`。
    func resolveRow(preferredModelName: String?) -> AIScenarioRemoteModelRow? {
        if let name = preferredModelName, name.isEmpty == false,
           let row = models.first(where: { $0.name == name })
        {
            return row
        }
        if defaultModelName.isEmpty == false,
           let row = models.first(where: { $0.name == defaultModelName })
        {
            return row
        }
        if let row = models.first(where: { $0.isDefault }) {
            return row
        }
        return models.first
    }

    func resolveConfig(preferredModelName: String?) -> AIScenarioConfig? {
        resolveRow(preferredModelName: preferredModelName)?.asScenarioConfig()
    }
}

extension AIScenarioRemoteBundlesCollection {
    mutating func setBundle(_ bundle: AIScenarioRemoteBundle, for scenario: AIScenario) {
        switch scenario {
        case .chat:
            chat = bundle
        case .embedding:
            embedding = bundle
        case .voice:
            voice = bundle
        case .medicalStructuredExtraction:
            medicalStructuredExtraction = bundle
        case .medicalDocumentTypeRecognition:
            medicalDocumentTypeRecognition = bundle
        case .medicalCaseExtraction:
            medicalCaseExtraction = bundle
        case .healthExamExtraction:
            healthExamExtraction = bundle
        case .medicalReportExtraction:
            medicalReportExtraction = bundle
        case .prescriptionExtraction:
            prescriptionExtraction = bundle
        case .medicationExtraction:
            medicationExtraction = bundle
        case .optimizationText:
            optimizationText = bundle
        case .optimizationVisual:
            optimizationVisual = bundle
        case .contextFolding:
            contextFolding = bundle
        case .router:
            router = bundle
        case .modelConfig:
            modelConfig = bundle
        case .reportInterpretation:
            reportInterpretation = bundle
        }
    }
}

/// bootstrap `scenarios` JSON 中的场景模型配置集合。
struct AIScenarioRemoteBundlesCollection: Codable, Equatable, Sendable {
    /// 对话场景模型集合。
    var chat: AIScenarioRemoteBundle
    /// 向量场景模型集合。
    var embedding: AIScenarioRemoteBundle
    /// 语音场景模型集合。
    var voice: AIScenarioRemoteBundle
    /// 医疗文档结构化抽取场景模型集合。
    var medicalStructuredExtraction: AIScenarioRemoteBundle
    /// 医疗文档类型识别场景模型集合。
    var medicalDocumentTypeRecognition: AIScenarioRemoteBundle
    /// 病例结构化抽取场景模型集合。
    var medicalCaseExtraction: AIScenarioRemoteBundle
    /// 体检报告结构化抽取场景模型集合。
    var healthExamExtraction: AIScenarioRemoteBundle
    /// 医疗报告结构化抽取场景模型集合。
    var medicalReportExtraction: AIScenarioRemoteBundle
    /// 处方结构化抽取场景模型集合。
    var prescriptionExtraction: AIScenarioRemoteBundle
    /// 用药结构化抽取场景模型集合。
    var medicationExtraction: AIScenarioRemoteBundle
    /// 文本优化场景模型集合。
    var optimizationText: AIScenarioRemoteBundle
    /// 视觉优化场景模型集合。
    var optimizationVisual: AIScenarioRemoteBundle
    /// 上下文折叠场景模型集合。
    var contextFolding: AIScenarioRemoteBundle
    /// 路由场景模型集合。
    var router: AIScenarioRemoteBundle
    /// 模型配置场景模型集合。
    var modelConfig: AIScenarioRemoteBundle
    /// 报告解读场景模型集合。
    var reportInterpretation: AIScenarioRemoteBundle

    init(
        chat: AIScenarioRemoteBundle,
        embedding: AIScenarioRemoteBundle,
        voice: AIScenarioRemoteBundle,
        medicalStructuredExtraction: AIScenarioRemoteBundle,
        medicalDocumentTypeRecognition: AIScenarioRemoteBundle,
        medicalCaseExtraction: AIScenarioRemoteBundle,
        healthExamExtraction: AIScenarioRemoteBundle,
        medicalReportExtraction: AIScenarioRemoteBundle,
        prescriptionExtraction: AIScenarioRemoteBundle,
        medicationExtraction: AIScenarioRemoteBundle,
        optimizationText: AIScenarioRemoteBundle,
        optimizationVisual: AIScenarioRemoteBundle,
        contextFolding: AIScenarioRemoteBundle,
        router: AIScenarioRemoteBundle,
        modelConfig: AIScenarioRemoteBundle,
        reportInterpretation: AIScenarioRemoteBundle
    ) {
        self.chat = chat
        self.embedding = embedding
        self.voice = voice
        self.medicalStructuredExtraction = medicalStructuredExtraction
        self.medicalDocumentTypeRecognition = medicalDocumentTypeRecognition
        self.medicalCaseExtraction = medicalCaseExtraction
        self.healthExamExtraction = healthExamExtraction
        self.medicalReportExtraction = medicalReportExtraction
        self.prescriptionExtraction = prescriptionExtraction
        self.medicationExtraction = medicationExtraction
        self.optimizationText = optimizationText
        self.optimizationVisual = optimizationVisual
        self.contextFolding = contextFolding
        self.router = router
        self.modelConfig = modelConfig
        self.reportInterpretation = reportInterpretation
    }

    /// 与服务端字段命名的映射。

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        chat = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("chat"))
        embedding = try c.decodeIfPresent(AIScenarioRemoteBundle.self, forKey: .key("embedding"))
            ?? AIScenarioRemoteBundle(defaultModelName: "", models: [])
        voice = try c.decodeIfPresent(AIScenarioRemoteBundle.self, forKey: .key("voice"))
            ?? AIScenarioRemoteBundle(defaultModelName: "", models: [])
        optimizationText = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("optimizationText"))
        optimizationVisual = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("optimizationVisual"))
        contextFolding = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("contextFolding"))
        router = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("router"))
        modelConfig = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("modelConfig"))
        reportInterpretation = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("reportInterpretation"))

        medicalStructuredExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("medicalStructuredExtraction"))
        medicalDocumentTypeRecognition = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("medicalDocumentTypeRecognition"))
        medicalCaseExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("medicalCaseExtraction"))
        healthExamExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("healthExamExtraction"))
        medicalReportExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("medicalReportExtraction"))
        prescriptionExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("prescriptionExtraction"))
        medicationExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .key("medicationExtraction"))
    }

    /// 根据业务场景取对应 bundle。
    func bundle(for scenario: AIScenario) -> AIScenarioRemoteBundle {
        switch scenario {
        case .chat:
            return chat
        case .embedding:
            return embedding
        case .voice:
            return voice
        case .medicalStructuredExtraction:
            return medicalStructuredExtraction
        case .medicalDocumentTypeRecognition:
            return medicalDocumentTypeRecognition
        case .medicalCaseExtraction:
            return medicalCaseExtraction
        case .healthExamExtraction:
            return healthExamExtraction
        case .medicalReportExtraction:
            return medicalReportExtraction
        case .prescriptionExtraction:
            return prescriptionExtraction
        case .medicationExtraction:
            return medicationExtraction
        case .optimizationText:
            return optimizationText
        case .optimizationVisual:
            return optimizationVisual
        case .contextFolding:
            return contextFolding
        case .router:
            return router
        case .modelConfig:
            return modelConfig
        case .reportInterpretation:
            return reportInterpretation
        }
    }

    func resolveRow(for scenario: AIScenario, preferredModelName: String?) -> AIScenarioRemoteModelRow? {
        bundle(for: scenario).resolveRow(preferredModelName: preferredModelName)
    }

    func resolveConfig(for scenario: AIScenario, preferredModelName: String?) -> AIScenarioConfig? {
        bundle(for: scenario).resolveConfig(preferredModelName: preferredModelName)
    }

    var allRows: [AIScenarioRemoteModelRow] {
        let bundles = [
            chat,
            embedding,
            voice,
            medicalStructuredExtraction,
            medicalDocumentTypeRecognition,
            medicalCaseExtraction,
            healthExamExtraction,
            medicalReportExtraction,
            prescriptionExtraction,
            medicationExtraction,
            optimizationText,
            optimizationVisual,
            contextFolding,
            router,
            modelConfig,
            reportInterpretation
        ]

        var seen = Set<String>()
        return bundles
            .flatMap(\.models)
            .filter { seen.insert($0.name).inserted }
    }

}
