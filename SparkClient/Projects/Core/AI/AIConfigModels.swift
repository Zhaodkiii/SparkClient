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

    /// 面向日志与上层展示的错误描述。
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid AI endpoint: \(endpoint)"
        case .missingScenario(let scenario):
            return "Missing AI config for scenario: \(scenario.rawValue)"
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
    /// 模型名称。
    var model: String
    /// 是否默认模型。
    var isDefault: Bool
    /// 身份标识（服务端可选，常用于角色/能力标签）。
    var identity: String?
    /// 温度参数。
    var temperature: Double
    /// 最大 token 数。
    var maxTokens: Int
    /// 请求地址（字符串形态）。
    var endpoint: String
    /// 模型级 API Key（可选）。
    var apiKey: String?
    /// 供应商公司（可选元数据）。
    var providerCompany: String?
    /// 供应商名称（可选元数据）。
    var providerName: String?

    /// 字段映射：
    /// - 兼容 snake_case 返回；
    /// - 本地统一 camelCase 命名，便于 Swift 侧调用。
    enum CodingKeys: String, CodingKey {
        case model
        case isDefault = "is_default"
        case identity
        case temperature
        case maxTokens = "max_tokens"
        case endpoint
        case apiKey = "api_key"
        case providerCompany = "provider_company"
        case providerName = "provider_name"
    }

    /// 将远端行配置降维成通用 `AIScenarioConfig`，用于后续统一处理。
    func asScenarioConfig() -> AIScenarioConfig {
        AIScenarioConfig(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

/// 单个场景的远端模型集合（包含默认模型名与候选模型列表）。
struct AIScenarioRemoteBundle: Codable, Equatable, Sendable {
    /// 默认模型名称（来自服务端 `default_model`）。
    var defaultModelName: String
    /// 候选模型行列表。
    var models: [AIScenarioRemoteModelRow]

    enum CodingKeys: String, CodingKey {
        case defaultModelName = "default_model"
        case models
    }

    /// 用单模型配置构造“多模型格式”兜底包。
    /// 使用场景：
    /// - 老数据仅有单模型配置；
    /// - 远端多模型 bootstrap 尚不可用时，统一走同一解析链路。
    static func singleModelFallback(_ config: AIScenarioConfig) -> AIScenarioRemoteBundle {
        let row = AIScenarioRemoteModelRow(
            model: config.model,
            isDefault: true,
            identity: "model",
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            endpoint: config.endpoint,
            apiKey: config.apiKey,
            providerCompany: nil,
            providerName: nil
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
           let row = models.first(where: { $0.model == name })
        {
            return row
        }
        if let row = models.first(where: { $0.isDefault }) {
            return row
        }
        return models.first
    }
}

/// bootstrap `scenarios` JSON 中的全部七个场景配置。
struct AIScenarioRemoteBundlesCollection: Codable, Equatable, Sendable {
    /// 对话场景模型集合。
    var chat: AIScenarioRemoteBundle
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

    /// 与服务端字段命名的映射。
    enum CodingKeys: String, CodingKey {
        case chat
        case optimizationText = "optimization_text"
        case optimizationVisual = "optimization_visual"
        case contextFolding = "context_folding"
        case router
        case modelConfig = "model_config"
        case reportInterpretation = "report_interpretation"
    }

    /// 根据业务场景取对应 bundle。
    /// 其中 `medicalStructuredExtraction` 目前先复用 `optimizationText`：
    /// - 便于在服务端尚未独立下发该场景时保持可用；
    /// - 后续服务端补齐后可平滑切换为独立配置。
    func bundle(for scenario: AIScenario) -> AIScenarioRemoteBundle {
        switch scenario {
        case .chat:
            return chat
        case .medicalStructuredExtraction:
            // 兼容新增场景：当前服务端尚未单独下发时，先复用文本抽取链路配置。
            return optimizationText
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

    /// 由旧版“扁平单模型配置快照”构造新版“多模型场景集合”。
    /// 目的：在迁移阶段保持数据结构统一，避免调用方分叉处理。
    static func seededFromFlatSnapshots(
        chat: AIScenarioConfig,
        optimizationText: AIScenarioConfig,
        optimizationVisual: AIScenarioConfig,
        contextFolding: AIScenarioConfig,
        router: AIScenarioConfig,
        modelConfig: AIScenarioConfig,
        reportInterpretation: AIScenarioConfig
    ) -> AIScenarioRemoteBundlesCollection {
        AIScenarioRemoteBundlesCollection(
            chat: .singleModelFallback(chat),
            optimizationText: .singleModelFallback(optimizationText),
            optimizationVisual: .singleModelFallback(optimizationVisual),
            contextFolding: .singleModelFallback(contextFolding),
            router: .singleModelFallback(router),
            modelConfig: .singleModelFallback(modelConfig),
            reportInterpretation: .singleModelFallback(reportInterpretation)
        )
    }
}
