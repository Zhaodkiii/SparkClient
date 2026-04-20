import Foundation

/// AI 配置来源。
/// - localDefault: 客户端内置默认值（兜底配置）。
/// - runtimeOverride: 运行期覆盖（如动态实验、调试开关或远端热更新映射后的本地覆盖）。
/// - trialPolicy: 试用策略下发的配置（例如限时试用期间指定的模型与参数）。
enum AIConfigSource: String, Codable, Sendable {
    case localDefault
    case runtimeOverride
    case trialPolicy
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
        maxTokens: Int = 2048
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
            return "Invalid AI endpoint: \(endpoint)"
        case .missingScenario(let scenario):
            return "Missing AI config for scenario: \(scenario.rawValue)"
        case .missingModelForScenario(let scenario):
            return "No AI model available for scenario: \(scenario.rawValue)"
        case .runtimeNotBootstrapped:
            return "AI runtime config is not ready"
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

    enum CodingKeys: String, CodingKey {
        case scenario
        case config
        case isDefault
    }

    /// 自定义解码：
    /// - 兼容历史数据中缺失 `isDefault` 的情况，默认回退为 `false`。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scenario = try c.decode(AIScenario.self, forKey: .scenario)
        config = try c.decode(AIScenarioConfig.self, forKey: .config)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    /// 自定义编码：显式输出全部字段，避免策略透传时语义丢失。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scenario, forKey: .scenario)
        try c.encode(config, forKey: .config)
        try c.encode(isDefault, forKey: .isDefault)
    }
}

// MARK: - 多模型场景启动配置（对应 `/api/v1/ai/config/bootstrap/` 的 `scenarios` 对象）

/// 场景下的一条模型配置（由 bootstrap 的 `default_model` 与 `models[]` 组成）。
struct AIScenarioRemoteModelRow: Codable, Equatable, Sendable {
    var name: String
    var displayName: String
    var identity: String
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
    var isDefault: Bool = false
    var temperature: Double = 0.2
    var maxTokens: Int = 4096

    var model: String {
        get { name }
        set { name = newValue }
    }

    var providerCompany: String? {
        company.isEmpty ? nil : company
    }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case isDefault = "is_default"
        case identity
        case company
        case supportsSearch = "supports_search"
        case supportsMultimodal = "supports_multimodal"
        case supportsReasoning = "supports_reasoning"
        case supportsToolUse = "supports_tool_use"
        case supportsVoiceGen = "supports_voice_gen"
        case supportsImageGen = "supports_image_gen"
        case supportsText = "supports_text"
        case supportsDeepReasoning = "supports_deep_reasoning"
        case reasoningControllable = "reasoning_controllable"
        case priceTier = "price_tier"
        case systemProvision
        case icon
        case briefDescription
        case source
        case aiScenarios
        case aiToolScenarios
        case temperature
        case maxTokens = "max_tokens"
        case endpoint
        case apiKey = "api_key"
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
}

/// 单个场景的远端模型集合（包含默认模型名与候选模型列表）。
struct AIScenarioRemoteBundle: Codable, Equatable, Sendable {
    /// 场景下默认模型名称。
    var defaultModelName: String
    /// 候选模型行列表。
    var models: [AIScenarioRemoteModelRow]

    enum CodingKeys: String, CodingKey {
        case defaultModelName = "default_model"
        case models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let models = try c.decode([AIScenarioRemoteModelRow].self, forKey: .models)
        let decodedDefault = try c.decodeIfPresent(String.self, forKey: .defaultModelName)?
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
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultModelName, forKey: .defaultModelName)
        try c.encode(models, forKey: .models)
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

enum AIScenarioDefaultModelStore {
    private static let keyPrefix = "spark.ai.default_model_name"

    static func userDefaultsKey(for scenario: AIScenario) -> String {
        "\(keyPrefix).\(scenario.rawValue)"
    }

    static func read(for scenario: AIScenario) -> String? {
        let value = UserDefaults.standard.string(forKey: userDefaultsKey(for: scenario))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    static func write(_ modelName: String?, for scenario: AIScenario) {
        let trimmed = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = userDefaultsKey(for: scenario)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    static func allScenarioDefaults(fallback: [String: String] = [:]) -> [String: String] {
        var out: [String: String] = fallback
        for scenario in AIScenario.allCases {
            if let stored = read(for: scenario) {
                out[scenario.rawValue] = stored
            }
        }
        return out
    }

    static func sync(from scenarioDefaults: [String: String]) {
        for scenario in AIScenario.allCases {
            write(scenarioDefaults[scenario.rawValue], for: scenario)
        }
    }
}

enum AIScenarioModelSourceStore {
    private static let keyPrefix = "spark.ai.model_source"

    static func userDefaultsKey(for scenario: AIScenario) -> String {
        "\(keyPrefix).\(scenario.rawValue)"
    }

    static func read(for scenario: AIScenario) -> AIModelSelectionSource? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey(for: scenario)) else { return nil }
        return AIModelSelectionSource(rawValue: raw)
    }

    static func write(_ source: AIModelSelectionSource, for scenario: AIScenario) {
        UserDefaults.standard.set(source.rawValue, forKey: userDefaultsKey(for: scenario))
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
    enum CodingKeys: String, CodingKey {
        case chat
        case embedding
        case voice
        case medicalStructuredExtraction = "medical_structured_extraction"
        case medicalDocumentTypeRecognition = "medical_document_type_recognition"
        case medicalCaseExtraction = "medical_case_extraction"
        case healthExamExtraction = "health_exam_extraction"
        case medicalReportExtraction = "medical_report_extraction"
        case prescriptionExtraction = "prescription_extraction"
        case medicationExtraction = "medication_extraction"
        case optimizationText = "optimization_text"
        case optimizationVisual = "optimization_visual"
        case contextFolding = "context_folding"
        case router
        case modelConfig = "model_config"
        case reportInterpretation = "report_interpretation"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chat = try c.decode(AIScenarioRemoteBundle.self, forKey: .chat)
        embedding = try c.decodeIfPresent(AIScenarioRemoteBundle.self, forKey: .embedding)
            ?? AIScenarioRemoteBundle(defaultModelName: "", models: [])
        voice = try c.decodeIfPresent(AIScenarioRemoteBundle.self, forKey: .voice)
            ?? AIScenarioRemoteBundle(defaultModelName: "", models: [])
        optimizationText = try c.decode(AIScenarioRemoteBundle.self, forKey: .optimizationText)
        optimizationVisual = try c.decode(AIScenarioRemoteBundle.self, forKey: .optimizationVisual)
        contextFolding = try c.decode(AIScenarioRemoteBundle.self, forKey: .contextFolding)
        router = try c.decode(AIScenarioRemoteBundle.self, forKey: .router)
        modelConfig = try c.decode(AIScenarioRemoteBundle.self, forKey: .modelConfig)
        reportInterpretation = try c.decode(AIScenarioRemoteBundle.self, forKey: .reportInterpretation)

        medicalStructuredExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .medicalStructuredExtraction)
        medicalDocumentTypeRecognition = try c.decode(AIScenarioRemoteBundle.self, forKey: .medicalDocumentTypeRecognition)
        medicalCaseExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .medicalCaseExtraction)
        healthExamExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .healthExamExtraction)
        medicalReportExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .medicalReportExtraction)
        prescriptionExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .prescriptionExtraction)
        medicationExtraction = try c.decode(AIScenarioRemoteBundle.self, forKey: .medicationExtraction)
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

}
