import Foundation

enum AIRecordSource: String, Codable, CaseIterable, Sendable {
    case system
    case custom
    case pro
}

enum AIModelIdentity: String, Codable, CaseIterable, Sendable {
    case model
    case agent
}

enum AIModelSelectionSource: String, Codable, CaseIterable, Sendable {
    case localKey
    case trial
}

nonisolated enum AIProviderIdentifier {
    nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9_\\-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }
}

nonisolated struct APIKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var providerID: String
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var help: String
    var from: String
    var privacyPolicyURL: String
    var isEnabled: Bool
    var source: AIRecordSource
    var privacyPolicyAccepted: Bool
    var privacyPolicyAcceptedAt: Date?
    var timestamp: Date

    var isHidden: Bool {
        get { !isEnabled }
        set { isEnabled = !newValue }
    }

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        help: String,
        from: String = AIRecordSource.system.rawValue,
        privacyPolicyURL: String = "",
        isEnabled: Bool = true,
        source: AIRecordSource,
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.help = help
        self.from = from
        self.privacyPolicyURL = privacyPolicyURL
        self.isEnabled = isEnabled
        self.source = source
        self.privacyPolicyAccepted = privacyPolicyAccepted
        self.privacyPolicyAcceptedAt = privacyPolicyAcceptedAt
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        isHidden: Bool,
        help: String,
        source: AIRecordSource,
        privacyPolicyURL: String = "",
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            providerID: providerID,
            name: name,
            company: company,
            key: key,
            requestURL: requestURL,
            help: help,
            from: source.rawValue,
            privacyPolicyURL: privacyPolicyURL,
            isEnabled: !isHidden,
            source: source,
            privacyPolicyAccepted: privacyPolicyAccepted,
            privacyPolicyAcceptedAt: privacyPolicyAcceptedAt,
            timestamp: timestamp
        )
    }


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .key("id")) ?? UUID()
        name = try container.decode(String.self, forKey: .key("name"))
        company = try container.decode(String.self, forKey: .key("company"))
        providerID = AIProviderIdentifier.normalize(
            try container.decodeIfPresent(String.self, forKey: .key("providerId")) ?? company
        )
        key = try container.decode(String.self, forKey: .key("key"))
        requestURL = try container.decode(String.self, forKey: .key("requestUrl"))
        help = try container.decodeIfPresent(String.self, forKey: .key("help")) ?? ""
        from = try container.decodeIfPresent(String.self, forKey: .key("from")) ?? AIRecordSource.system.rawValue
        privacyPolicyURL = try container.decodeIfPresent(String.self, forKey: .key("privacyPolicyUrl")) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .key("isEnabled")) ?? true
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .key("source")) ?? AIRecordSource(rawValue: from.lowercased()) ?? .system
        privacyPolicyAccepted = try container.decodeIfPresent(Bool.self, forKey: .key("privacyPolicyAccepted")) ?? false
        privacyPolicyAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .key("privacyPolicyAcceptedAt"))
        timestamp = try container.decodeIfPresent(Date.self, forKey: .key("timestamp")) ?? Date()
    }
}

nonisolated struct SearchKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var searchClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date
    var authType: SearchProviderAuthType = .bearer
    var priority: Int = 0
    var enabledScopes: [String] = ["chat", "small_task"]
    var revision: Int = 1

    init(
        id: UUID = UUID(),
        name: String,
        company: String,
        key: String,
        requestURL: String,
        isUsing: Bool,
        searchClass: String,
        help: String,
        source: AIRecordSource,
        timestamp: Date,
        authType: SearchProviderAuthType = .bearer,
        priority: Int = 0,
        enabledScopes: [String] = ["chat", "small_task"],
        revision: Int = 1
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.isUsing = isUsing
        self.searchClass = searchClass
        self.help = help
        self.source = source
        self.timestamp = timestamp
        self.authType = authType
        self.priority = priority
        self.enabledScopes = enabledScopes
        self.revision = revision
    }


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .key("id")) ?? UUID()
        name = try container.decode(String.self, forKey: .key("name"))
        company = try container.decode(String.self, forKey: .key("company"))
        key = try container.decodeIfPresent(String.self, forKey: .key("key")) ?? ""
        requestURL = try container.decode(String.self, forKey: .key("requestUrl"))
        isUsing = try container.decodeIfPresent(Bool.self, forKey: .key("isUsing")) ?? false
        searchClass = try container.decodeIfPresent(String.self, forKey: .key("searchClass")) ?? "web"
        help = try container.decodeIfPresent(String.self, forKey: .key("help")) ?? ""
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .key("source")) ?? .system
        timestamp = try container.decodeIfPresent(Date.self, forKey: .key("timestamp")) ?? Date()
        authType = try container.decodeIfPresent(SearchProviderAuthType.self, forKey: .key("authType")) ?? .bearer
        priority = try container.decodeIfPresent(Int.self, forKey: .key("priority")) ?? 0
        enabledScopes = try container.decodeIfPresent([String].self, forKey: .key("enabledScopes")) ?? ["chat", "small_task"]
        revision = try container.decodeIfPresent(Int.self, forKey: .key("revision")) ?? 1
    }
}

enum SearchProviderAuthType: String, Codable, Equatable, Sendable {
    case bearer
    case headerToken
    case queryAPIKey
    case none
}

nonisolated struct SearchRuntimeConfigRevision: Codable, Equatable, Sendable {
    nonisolated static let schemaVersion = 1

    var schemaVersion: Int
    var localRevision: Int
    var updatedAt: Date
    var activeSearchKeyID: UUID?
    var preferencesHash: String

    init(
        schemaVersion: Int = SearchRuntimeConfigRevision.schemaVersion,
        localRevision: Int = 1,
        updatedAt: Date = Date(),
        activeSearchKeyID: UUID? = nil,
        preferencesHash: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.localRevision = localRevision
        self.updatedAt = updatedAt
        self.activeSearchKeyID = activeSearchKeyID
        self.preferencesHash = preferencesHash
    }
}

nonisolated struct ToolKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var toolClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date
}

nonisolated struct AllModels: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var displayName: String
    var identity: AIModelIdentity
    var position: Int
    var providerID: String
    var company: String
    var price: Int
    var isEnabled: Bool
    var supportsSearch: Bool
    var supportsTextGen: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportReasoningChange: Bool
    var supportsImageGen: Bool
    var supportsVoiceGen: Bool
    var supportsToolUse: Bool
    var systemProvision: String
    var icon: String
    var briefDescription: String
    var characterDesign: String
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var baseModelName: String?
    var localFilename: String?
    var source: AIRecordSource
    var timestamp: Date

    var isHidden: Bool {
        get { !isEnabled }
        set { isEnabled = !newValue }
    }

    var priceTier: Int {
        get { price }
        set { price = newValue }
    }

    var supportsText: Bool {
        get { supportsTextGen }
        set { supportsTextGen = newValue }
    }

    var reasoningControllable: Bool {
        get { supportReasoningChange }
        set { supportReasoningChange = newValue }
    }

    var iconSymbol: String? {
        get { icon.isEmpty ? nil : icon }
        set { icon = newValue ?? "" }
    }

    var systemPrompt: String? {
        get { systemProvision.isEmpty ? nil : systemProvision }
        set { systemProvision = newValue ?? "" }
    }

    /// 工具选择：空数组视为“默认全选”，哨兵值视为“明确全不选”。
    var selectedToolNames: Set<String> {
        get {
            SparkToolName.selectedSet(fromStoredToolNames: aiToolScenarios)
        }
        set {
            aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: newValue)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        price: Int = 0,
        isEnabled: Bool = true,
        supportsSearch: Bool,
        supportsTextGen: Bool = true,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportReasoningChange: Bool = false,
        supportsImageGen: Bool,
        supportsVoiceGen: Bool,
        supportsToolUse: Bool,
        systemProvision: String = "",
        icon: String = "",
        briefDescription: String = "",
        characterDesign: String = "",
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        baseModelName: String? = nil,
        localFilename: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.position = position
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.company = company
        self.price = price
        self.isEnabled = isEnabled
        self.supportsSearch = supportsSearch
        self.supportsTextGen = supportsTextGen
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.supportsImageGen = supportsImageGen
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsToolUse = supportsToolUse
        self.systemProvision = systemProvision
        self.icon = icon
        self.briefDescription = briefDescription
        self.characterDesign = characterDesign
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.baseModelName = baseModelName
        self.localFilename = localFilename
        self.source = source
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        isHidden: Bool,
        supportsSearch: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportsToolUse: Bool,
        supportsVoiceGen: Bool,
        supportsImageGen: Bool,
        iconSymbol: String? = nil,
        baseModelName: String? = nil,
        localFilename: String? = nil,
        systemPrompt: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date(),
        priceTier: Int = 0,
        supportsText: Bool = true,
        reasoningControllable: Bool = false,
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = []
    ) {
        self.init(
            id: id,
            name: name,
            displayName: displayName,
            identity: identity,
            position: position,
            providerID: providerID,
            company: company,
            price: priceTier,
            isEnabled: !isHidden,
            supportsSearch: supportsSearch,
            supportsTextGen: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: reasoningControllable,
            supportsImageGen: supportsImageGen,
            supportsVoiceGen: supportsVoiceGen,
            supportsToolUse: supportsToolUse,
            systemProvision: systemPrompt ?? "",
            icon: iconSymbol ?? "",
            briefDescription: "",
            characterDesign: "",
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            baseModelName: baseModelName,
            localFilename: localFilename,
            source: source,
            timestamp: timestamp
        )
    }


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .key("id")) ?? UUID()
        name = try container.decode(String.self, forKey: .key("name"))
        displayName = try container.decode(String.self, forKey: .key("displayName"))
        identity = try container.decodeIfPresent(AIModelIdentity.self, forKey: .key("identity")) ?? .model
        position = try container.decodeIfPresent(Int.self, forKey: .key("position")) ?? 0
        company = try container.decode(String.self, forKey: .key("company"))
        providerID = AIProviderIdentifier.normalize(
            try container.decodeIfPresent(String.self, forKey: .key("providerId")) ?? company
        )
        price = try container.decodeIfPresent(Int.self, forKey: .key("price")) ?? 0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .key("isEnabled")) ?? true
        supportsSearch = try container.decodeIfPresent(Bool.self, forKey: .key("supportsSearch")) ?? true
        supportsTextGen = try container.decodeIfPresent(Bool.self, forKey: .key("supportsTextGen")) ?? true
        supportsMultimodal = try container.decodeIfPresent(Bool.self, forKey: .key("supportsMultimodal")) ?? false
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .key("supportsReasoning")) ?? false
        supportReasoningChange = try container.decodeIfPresent(Bool.self, forKey: .key("supportReasoningChange")) ?? false
        supportsImageGen = try container.decodeIfPresent(Bool.self, forKey: .key("supportsImageGen")) ?? false
        supportsVoiceGen = try container.decodeIfPresent(Bool.self, forKey: .key("supportsVoiceGen")) ?? false
        supportsToolUse = try container.decodeIfPresent(Bool.self, forKey: .key("supportsToolUse")) ?? false
        systemProvision = try container.decodeIfPresent(String.self, forKey: .key("systemProvision")) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .key("icon")) ?? ""
        briefDescription = try container.decodeIfPresent(String.self, forKey: .key("briefDescription")) ?? ""
        characterDesign = try container.decodeIfPresent(String.self, forKey: .key("characterDesign")) ?? ""
        aiToolScenarios = try container.decodeIfPresent([String].self, forKey: .key("aiToolScenarios")) ?? []
        relatedTaskCodes = try container.decodeIfPresent([String].self, forKey: .key("relatedTaskCodes")) ?? []
        baseModelName = try container.decodeIfPresent(String.self, forKey: .key("baseModelName"))
        localFilename = try container.decodeIfPresent(String.self, forKey: .key("localFilename"))
        source = try container.decodeIfPresent(AIRecordSource.self, forKey: .key("source")) ?? .system
        timestamp = try container.decodeIfPresent(Date.self, forKey: .key("timestamp")) ?? Date()
    }

    var isLocalModel: Bool {
        providerID == LocalModelService.localProviderID && identity == .model
    }

    var isLocalAgent: Bool {
        providerID == LocalModelService.localProviderID && identity == .agent
    }
}

nonisolated struct AIScenarioModelBinding: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var ownerAccountID: Int64
    var scenario: String
    var identity: AIModelIdentity
    var modelID: UUID
    var temperature: Double
    var maxTokens: Int
    var position: Int
    var isDefault: Bool
    var isActive: Bool
    var systemProvision: String
    var briefDescription: String
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerAccountID: Int64 = 0,
        scenario: String,
        identity: AIModelIdentity = .model,
        modelID: UUID,
        temperature: Double = Self.defaultTemperature,
        maxTokens: Int = Self.defaultMaxTokens,
        position: Int = 0,
        isDefault: Bool = false,
        isActive: Bool = true,
        systemProvision: String = "",
        briefDescription: String = "",
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.scenario = scenario
        self.identity = identity
        self.modelID = modelID
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.position = position
        self.isDefault = isDefault
        self.isActive = isActive
        self.systemProvision = systemProvision
        self.briefDescription = briefDescription
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated extension AIScenarioModelBinding {
    nonisolated static let defaultTemperature: Double = 0.68
    nonisolated static let defaultMaxTokens: Int = 12_800

    var scenarioKey: AIScenario? {
        AIScenario(rawValue: scenario)
    }
}

nonisolated struct AIWeatherToolPreferences: Codable, Equatable, Sendable {
    var useWeather: Bool

    init(useWeather: Bool = true) {
        self.useWeather = useWeather
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        useWeather = try container.decodeIfPresent(Bool.self, forKey: .key("useWeather")) ?? true
    }
}

nonisolated struct AISearchToolPreferences: Codable, Equatable, Sendable {
    var useKnowledge: Bool
    var knowledgeCount: Int
    var knowledgeSimilarity: Double
    var useSearch: Bool
    var bilingualSearch: Bool
    var searchCount: Int

    init(
        useKnowledge: Bool,
        knowledgeCount: Int,
        knowledgeSimilarity: Double,
        useSearch: Bool,
        bilingualSearch: Bool,
        searchCount: Int
    ) {
        self.useKnowledge = useKnowledge
        self.knowledgeCount = knowledgeCount
        self.knowledgeSimilarity = knowledgeSimilarity
        self.useSearch = useSearch
        self.bilingualSearch = bilingualSearch
        self.searchCount = searchCount
    }


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        useKnowledge = try container.decodeIfPresent(Bool.self, forKey: .key("useKnowledge")) ?? true
        knowledgeCount = try container.decodeIfPresent(Int.self, forKey: .key("knowledgeCount")) ?? 12
        knowledgeSimilarity = try container.decodeIfPresent(Double.self, forKey: .key("knowledgeSimilarity")) ?? 0.55
        useSearch = try container.decodeIfPresent(Bool.self, forKey: .key("useSearch")) ?? true
        bilingualSearch = try container.decodeIfPresent(Bool.self, forKey: .key("bilingualSearch")) ?? true
        searchCount = try container.decodeIfPresent(Int.self, forKey: .key("searchCount")) ?? 8
    }
}


/// 提示词仓库模型（用于存储、管理 AI 系统提示词）
/// 支持：自定义提示词 + 内置预设提示词（多语言本地化）
nonisolated struct PromptRepo: Identifiable, Codable, Equatable, Sendable {
    /// 唯一标识 ID
    var id: UUID = UUID()
    /// 提示词标题（原始文本）
    var title: String
    /// 提示词内容（原始文本）
    var content: String
    /// 是否为系统预设提示词（true = 内置预设，false = 用户自定义）
    var isSystem: Bool
    /// 创建/更新时间戳
    var timestamp: Date
    /// 多语言本地化 Key（内置预设提示词使用）
    var localizationKey: String? = nil

    // MARK: - 本地化计算属性

    /// 本地化后的标题（优先读取多语言配置，无则返回原始标题）
    var localizedTitle: String {
        // 获取本地化 Key：优先使用自身属性，否则兼容旧版通过标题/内容匹配
        guard let localizationKey = localizationKey ?? Self.legacyLocalizationKey(title: title, content: content) else {
            return title
        }
        // 从多语言配置读取文本，读取失败则使用原始标题作为兜底
        return L10n.text("ai_settings.prompt_repo.preset.\(localizationKey).title", fallback: title)
    }

    /// 本地化后的内容（优先读取多语言配置，无则返回原始内容）
    var localizedContent: String {
        guard let localizationKey = localizationKey ?? Self.legacyLocalizationKey(title: title, content: content) else {
            return content
        }
        return L10n.text("ai_settings.prompt_repo.preset.\(localizationKey).content", fallback: content)
    }

    // MARK: - 旧版兼容：根据原始标题/内容自动匹配本地化 Key

    /// 【旧版兼容方法】
    /// 针对没有设置 localizationKey 的预设提示词
    /// 根据原始的中英文标题+内容，自动返回对应的本地化 Key
    private static func legacyLocalizationKey(title: String, content: String) -> String? {
        // 去除首尾空白、换行，避免格式差异导致匹配失败
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 匹配已知的内置预设提示词，返回对应的 localizationKey
        switch (normalizedTitle, normalizedContent) {
        // 健康助手默认提示词
        case ("健康助手默认提示词", "你是一位专业健康助手。回答要分层：先结论，再行动建议，再风险提示；避免绝对化诊断。"),
             ("Health assistant default prompt", "You are a professional health assistant. Structure answers with: conclusion first, actionable suggestions next, and risk notes last. Avoid absolute diagnoses."):
            return "health_assistant"
        // 医学抽取结构化模板
        case ("医学抽取结构化模板", "从输入文本提取：主诉、现病史、既往史、过敏史、用药史、检查结果、评估与建议。缺失字段返回 null。"),
             ("Medical extraction template", "Extract from the input text: chief complaint, present illness, past history, allergy history, medication history, test results, assessment, and recommendations. Return null for missing fields."):
            return "medical_extraction"
        // 知识召回增强模板
        case ("知识召回增强模板", "优先使用召回知识回答；若知识不足，明确说明不确定性并给出后续补充信息建议。"),
             ("Knowledge recall enhancement template", "Prioritize recalled knowledge when answering. If the knowledge is insufficient, clearly state uncertainty and suggest what additional information is needed."):
            return "knowledge_recall"
        // 双语医学解释模板
        case ("双语医学解释模板", "先用中文解释医学术语，再给出英文对应术语和一句简明定义，保持术语一致。"),
             ("Bilingual medical explanation", "Explain the medical term in Chinese first, then provide the English term and one concise definition. Keep terminology consistent."):
            return "bilingual_medical"
        // 无匹配
        default:
            return nil
        }
    }
}

nonisolated struct MemoryArchive: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var pinned: Bool
    var timestamp: Date
}

nonisolated struct TranslationDic: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var sourceText: String
    var targetText: String
    var note: String
    var timestamp: Date
}

nonisolated enum AISettingsDefaults {
    nonisolated static var apiKeys: [APIKeys] {
        let timestamp = Date()
        return [
            APIKeys(
                name: "Spark Default",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/chat/completions",
                isHidden: false,
                help: "Spark first-party endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Spark Embedding",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/embeddings",
                isHidden: false,
                help: "Spark first-party embedding endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Spark TTS",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/audio/speech",
                isHidden: false,
                help: "Spark first-party text-to-speech endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "OpenAI",
                company: "OPENAI",
                key: "",
                requestURL: "https://api.openai.com/v1/chat/completions",
                isHidden: true,
                help: "OpenAI compatible endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Anthropic",
                company: "ANTHROPIC",
                key: "",
                requestURL: "https://api.anthropic.com/v1/messages",
                isHidden: true,
                help: "Claude models endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Google Gemini",
                company: "GOOGLE",
                key: "",
                requestURL: "https://generativelanguage.googleapis.com/v1beta/models",
                isHidden: true,
                help: "Gemini models endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Qwen",
                company: "QWEN",
                key: "",
                requestURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                isHidden: true,
                help: "Qwen compatible endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "DeepSeek",
                company: "DEEPSEEK",
                key: "",
                requestURL: "https://api.deepseek.com/v1/chat/completions",
                isHidden: true,
                help: "DeepSeek official endpoint",
                source: .system,
                timestamp: timestamp
            ),
            APIKeys(
                name: "Zhipu",
                company: "ZHIPUAI",
                key: "",
                requestURL: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
                isHidden: true,
                help: "GLM model endpoint",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    nonisolated static var searchKeys: [SearchKeys] {
        let timestamp = Date()
        return [
            SearchKeys(
                name: "智谱清言搜索",
                company: "ZHIPUAI",
                key: "",
                requestURL: "https://open.bigmodel.cn/api/paas/v4/web_search",
                isUsing: false,
                searchClass: "web",
                help: "智谱 Web Search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "博查AI",
                company: "BOCHAAI",
                key: "",
                requestURL: "https://api.bochaai.com/v1/web-search",
                isUsing: false,
                searchClass: "web",
                help: "博查 Web Search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "LangSearch",
                company: "LANGSEARCH",
                key: "",
                requestURL: "https://api.langsearch.com/v1/web-search",
                isUsing: false,
                searchClass: "web",
                help: "LangSearch Web Search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "Exa",
                company: "EXA",
                key: "",
                requestURL: "https://api.exa.ai/search",
                isUsing: false,
                searchClass: "web",
                help: "Exa neural search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "Tavily",
                company: "TAVILY",
                key: "",
                requestURL: "https://api.tavily.com/search",
                isUsing: false,
                searchClass: "web",
                help: "Tavily Web Search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "Brave Search",
                company: "BRAVE",
                key: "",
                requestURL: "https://api.search.brave.com/res/v1/web/search",
                isUsing: false,
                searchClass: "web",
                help: "Brave Search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "Perplexity",
                company: "PERPLEXITY",
                key: "",
                requestURL: "https://api.perplexity.ai/chat/completions",
                isUsing: false,
                searchClass: "web",
                help: "Perplexity Sonar web search API",
                source: .system,
                timestamp: timestamp
            ),
            SearchKeys(
                name: "SerpAPI",
                company: "SERPAPI",
                key: "",
                requestURL: "https://serpapi.com/search.json",
                isUsing: false,
                searchClass: "web",
                help: "SerpAPI search endpoint",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    nonisolated static var toolKeys: [ToolKeys] {
        let timestamp = Date()
        return [
            ToolKeys(
                name: "Spark Tools",
                company: "SPARK",
                key: "",
                requestURL: "https://api.sparkclient.local/v1/tools",
                isUsing: true,
                toolClass: "tool",
                help: "Default tool routing endpoint",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "OPENWEATHER_KEY",
                company: "OPENWEATHER",
                key: "",
                requestURL: "api.openweathermap.org",
                isUsing: false,
                toolClass: "weather",
                help: "https://home.openweathermap.org/api_keys",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "QWEATHER_KEY",
                company: "QWEATHER",
                key: "",
                requestURL: "",
                isUsing: false,
                toolClass: "weather",
                help: "https://console.qweather.com/project?lang=zh",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "APPLEWEATHER_KEY",
                company: "APPLEWEATHER",
                key: "",
                requestURL: "",
                isUsing: false,
                toolClass: "weather",
                help: "https://developer.apple.com/documentation/weatherkit",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "Google Maps",
                company: "GOOGLE",
                key: "",
                requestURL: "https://maps.googleapis.com/maps/api/geocode/json",
                isUsing: false,
                toolClass: "map",
                help: "Map and geocode tool",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "Google Calendar",
                company: "GOOGLE",
                key: "",
                requestURL: "https://www.googleapis.com/calendar/v3",
                isUsing: false,
                toolClass: "calendar",
                help: "Calendar integration tool",
                source: .system,
                timestamp: timestamp
            ),
            ToolKeys(
                name: "GitHub Code Search",
                company: "GITHUB",
                key: "",
                requestURL: "https://api.github.com/search/code",
                isUsing: false,
                toolClass: "code",
                help: "Code search tool for repositories",
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    nonisolated static var allModels: [AllModels] {
        let timestamp = Date()
        return [
            AllModels(
                name: "spark-chat-default",
                displayName: "Spark Chat",
                identity: .model,
                position: 1,
                company: "SPARK",
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-medical-extraction",
                displayName: "Spark Medical Extraction",
                identity: .model,
                position: 2,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-embedding-default",
                displayName: "Spark Embedding",
                identity: .model,
                position: 3,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-tts-default",
                displayName: "Spark TTS",
                identity: .model,
                position: 4,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: true,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-optimization-default",
                displayName: "Spark Optimization",
                identity: .model,
                position: 5,
                company: "SPARK",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gpt-5",
                displayName: "GPT-5",
                identity: .model,
                position: 10,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gpt-5-mini",
                displayName: "GPT-5 Mini",
                identity: .model,
                position: 11,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "o4-mini",
                displayName: "o4-mini",
                identity: .model,
                position: 12,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "claude-sonnet-4-5",
                displayName: "Claude Sonnet 4.5",
                identity: .model,
                position: 20,
                company: "ANTHROPIC",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "claude-3-7-sonnet",
                displayName: "Claude 3.7 Sonnet",
                identity: .model,
                position: 21,
                company: "ANTHROPIC",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gemini-2.5-pro",
                displayName: "Gemini 2.5 Pro",
                identity: .model,
                position: 30,
                company: "GOOGLE",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "gemini-2.5-flash",
                displayName: "Gemini 2.5 Flash",
                identity: .model,
                position: 31,
                company: "GOOGLE",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: true,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "qwen3-max",
                displayName: "Qwen3 Max",
                identity: .model,
                position: 40,
                company: "QWEN",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "qwen-plus",
                displayName: "Qwen Plus",
                identity: .model,
                position: 41,
                company: "QWEN",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "deepseek-chat",
                displayName: "DeepSeek Chat",
                identity: .model,
                position: 50,
                company: "DEEPSEEK",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "deepseek-reasoner",
                displayName: "DeepSeek Reasoner",
                identity: .model,
                position: 51,
                company: "DEEPSEEK",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "glm-4.5",
                displayName: "GLM 4.5",
                identity: .model,
                position: 60,
                company: "ZHIPUAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "glm-4.5v",
                displayName: "GLM 4.5V",
                identity: .model,
                position: 61,
                company: "ZHIPUAI",
                isHidden: true,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "text-embedding-3-large",
                displayName: "Embedding Large",
                identity: .model,
                position: 70,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "text-embedding-3-small",
                displayName: "Embedding Small",
                identity: .model,
                position: 71,
                company: "OPENAI",
                isHidden: true,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            ),
            AllModels(
                name: "spark-agent-doctor",
                displayName: "Spark Doctor Agent",
                identity: .agent,
                position: 80,
                company: "SPARK",
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: true,
                supportsImageGen: false,
                source: .system,
                timestamp: timestamp
            )
        ]
    }

    nonisolated static var searchToolPreferences: AISearchToolPreferences {
        AISearchToolPreferences(
            useKnowledge: true,
            knowledgeCount: 12,
            knowledgeSimilarity: 0.55,
            useSearch: true,
            bilingualSearch: true,
            searchCount: 8
        )
    }

    nonisolated static var weatherToolPreferences: AIWeatherToolPreferences {
        AIWeatherToolPreferences(useWeather: true)
    }

    nonisolated static var promptRepo: [PromptRepo] {
        let timestamp = Date()
        return [
            PromptRepo(
                title: L10n.text("ai_settings.prompt_repo.preset.health_assistant.title", fallback: "健康助手默认提示词"),
                content: L10n.text("ai_settings.prompt_repo.preset.health_assistant.content", fallback: "你是一位专业健康助手。回答要分层：先结论，再行动建议，再风险提示；避免绝对化诊断。"),
                isSystem: true,
                timestamp: timestamp,
                localizationKey: "health_assistant"
            ),
            PromptRepo(
                title: L10n.text("ai_settings.prompt_repo.preset.medical_extraction.title", fallback: "医学抽取结构化模板"),
                content: L10n.text("ai_settings.prompt_repo.preset.medical_extraction.content", fallback: "从输入文本提取：主诉、现病史、既往史、过敏史、用药史、检查结果、评估与建议。缺失字段返回 null。"),
                isSystem: true,
                timestamp: timestamp,
                localizationKey: "medical_extraction"
            ),
            PromptRepo(
                title: L10n.text("ai_settings.prompt_repo.preset.knowledge_recall.title", fallback: "知识召回增强模板"),
                content: L10n.text("ai_settings.prompt_repo.preset.knowledge_recall.content", fallback: "优先使用召回知识回答；若知识不足，明确说明不确定性并给出后续补充信息建议。"),
                isSystem: true,
                timestamp: timestamp,
                localizationKey: "knowledge_recall"
            ),
            PromptRepo(
                title: L10n.text("ai_settings.prompt_repo.preset.bilingual_medical.title", fallback: "双语医学解释模板"),
                content: L10n.text("ai_settings.prompt_repo.preset.bilingual_medical.content", fallback: "先用中文解释医学术语，再给出英文对应术语和一句简明定义，保持术语一致。"),
                isSystem: true,
                timestamp: timestamp,
                localizationKey: "bilingual_medical"
            )
        ]
    }

    nonisolated static var memoryArchive: [MemoryArchive] {
        []
    }

    nonisolated static var translationDic: [TranslationDic] {
        let timestamp = Date()
        return [
            TranslationDic(
                sourceText: "HbA1c",
                targetText: "糖化血红蛋白",
                note: "反映近 2-3 个月平均血糖",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "SBP",
                targetText: "收缩压",
                note: "高压",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "DBP",
                targetText: "舒张压",
                note: "低压",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "BMI",
                targetText: "体质指数",
                note: "体重(kg)/身高(m)^2",
                timestamp: timestamp
            ),
            TranslationDic(
                sourceText: "eGFR",
                targetText: "估算肾小球滤过率",
                note: "用于评估肾功能",
                timestamp: timestamp
            )
        ]
    }
}
