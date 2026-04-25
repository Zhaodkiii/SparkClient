import Foundation

/// 按账号存于 Core Data 的 AI 设置快照（含 `allModels` / `apiKeys`）。
/// 已登录冷启动：`AppBootstrapper.bootstrapIfNeeded(for:)` 以 `UserSession.accountID` 调用 `AIConfigCenter.prewarm` 写入运行时缓存；设置页 `AISettingsViewModel` 应传入同一 `ownerAccountID` 加载目录，避免依赖会话快照解析顺序。
struct AISettingsSnapshot: Codable, Equatable, Sendable {
    var allModels: [AllModels]
    var apiKeys: [APIKeys]
    var smallTasks: [SmallTask]
    /// 检索与知识相关本地偏好。
    var searchToolPreferences: AISearchToolPreferences
    /// 场景级默认模型（`AIScenario.rawValue` -> 模型 `name`）。
    var scenarioDefaultModels: [String: String]
    /// 场景级模型来源选择（`AIScenario.rawValue` -> `AIModelSelectionSource.rawValue`）。
    var scenarioModelSources: [String: AIModelSelectionSource]
    /// 输入栏中隐藏的试用模型名（仅本地偏好）。
    var trialChatPickerDisabledModelNames: [String]
    /// 试用状态（内存偏好，持久化于 UserDefaults payload）。
    var trial: AITrialState
    var trialModelPolicy: [AITrialModelPolicyItem]
    var searchKeys: [SearchKeys]
    var toolKeys: [ToolKeys]
    var promptRepo: [PromptRepo]
    var memoryArchive: [MemoryArchive]
    var translationDic: [TranslationDic]

    init(
        allModels: [AllModels],
        apiKeys: [APIKeys],
        smallTasks: [SmallTask] = [],
        searchToolPreferences: AISearchToolPreferences = AISettingsDefaults.searchToolPreferences,
        scenarioDefaultModels: [String: String] = [:],
        scenarioModelSources: [String: AIModelSelectionSource] = [:],
        trialChatPickerDisabledModelNames: [String] = [],
        trial: AITrialState = .inactive,
        trialModelPolicy: [AITrialModelPolicyItem] = [],
        searchKeys: [SearchKeys] = [],
        toolKeys: [ToolKeys] = [],
        promptRepo: [PromptRepo] = [],
        memoryArchive: [MemoryArchive] = [],
        translationDic: [TranslationDic] = []
    ) {
        self.allModels = allModels
        self.apiKeys = apiKeys
        self.smallTasks = smallTasks
        self.searchToolPreferences = searchToolPreferences
        self.scenarioDefaultModels = scenarioDefaultModels
        self.scenarioModelSources = scenarioModelSources
        self.trialChatPickerDisabledModelNames = trialChatPickerDisabledModelNames
        self.trial = trial
        self.trialModelPolicy = trialModelPolicy
        self.searchKeys = searchKeys
        self.toolKeys = toolKeys
        self.promptRepo = promptRepo
        self.memoryArchive = memoryArchive
        self.translationDic = translationDic
    }

    /// 内存默认态：目录数据以 Core Data 为准，不在此处读取 `AllModels.json` / `APIKeys.json`。
    static let `default` = AISettingsSnapshot(
        allModels: [],
        apiKeys: [],
        smallTasks: [],
        searchToolPreferences: AISettingsDefaults.searchToolPreferences,
        scenarioDefaultModels: [:],
        scenarioModelSources: [:],
        trialChatPickerDisabledModelNames: [],
        trial: .inactive,
        trialModelPolicy: [],
        searchKeys: AISettingsDefaults.searchKeys,
        toolKeys: AISettingsDefaults.toolKeys,
        promptRepo: AISettingsDefaults.promptRepo,
        memoryArchive: AISettingsDefaults.memoryArchive,
        translationDic: AISettingsDefaults.translationDic
    )

    func chatTrialPolicyModelNames() -> [String] {
        trialModelPolicy
            .filter { $0.scenario == .chat }
            .map(\.config.model)
    }

    func trialPolicyConfig(for scenario: AIScenario) -> AIScenarioConfig? {
        trialModelPolicy.first(where: { $0.scenario == scenario && $0.isDefault })?.config
            ?? trialModelPolicy.first(where: { $0.scenario == scenario })?.config
    }

    func scenarioDefaultModelName(for scenario: AIScenario) -> String? {
        let value = scenarioDefaultModels[scenario.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    func scenarioModelSource(for scenario: AIScenario) -> AIModelSelectionSource {
        scenarioModelSources[scenario.rawValue] ?? .localKey
    }

    mutating func setScenarioDefaultModelName(_ modelName: String?, for scenario: AIScenario) {
        let trimmed = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            scenarioDefaultModels.removeValue(forKey: scenario.rawValue)
        } else {
            scenarioDefaultModels[scenario.rawValue] = trimmed
        }
    }

    mutating func setScenarioModelSource(_ source: AIModelSelectionSource, for scenario: AIScenario) {
        scenarioModelSources[scenario.rawValue] = source
    }
}

// MARK: - 偏好持久化载荷（与快照非目录字段一致）

extension AISettingsSnapshot {
    /// 与 `AISettingsSnapshot` 中除 `allModels` / `apiKeys` 外的字段一一对应，供账号级 UserDefaults 序列化；
    /// 仓储层只对该类型做 `JSONEncoder` / `JSONDecoder`，避免重复结构体与手写映射。
    struct PreferencesPayload: Codable, Equatable, Sendable {
        var searchToolPreferences: AISearchToolPreferences
        var scenarioDefaultModels: [String: String]
        var scenarioModelSources: [String: AIModelSelectionSource]
        var trialChatPickerDisabledModelNames: [String]
        var trial: AITrialState
        var trialModelPolicy: [AITrialModelPolicyItem]
        var searchKeys: [SearchKeys]
        var toolKeys: [ToolKeys]
        var promptRepo: [PromptRepo]
        var memoryArchive: [MemoryArchive]
        var translationDic: [TranslationDic]

        static let `default` = PreferencesPayload(
            searchToolPreferences: AISettingsDefaults.searchToolPreferences,
            scenarioDefaultModels: [:],
            scenarioModelSources: [:],
            trialChatPickerDisabledModelNames: [],
            trial: .inactive,
            trialModelPolicy: [],
            searchKeys: AISettingsDefaults.searchKeys,
            toolKeys: AISettingsDefaults.toolKeys,
            promptRepo: AISettingsDefaults.promptRepo,
            memoryArchive: AISettingsDefaults.memoryArchive,
            translationDic: AISettingsDefaults.translationDic
        )

        init(
            searchToolPreferences: AISearchToolPreferences,
            scenarioDefaultModels: [String: String],
            scenarioModelSources: [String: AIModelSelectionSource],
            trialChatPickerDisabledModelNames: [String],
            trial: AITrialState,
            trialModelPolicy: [AITrialModelPolicyItem],
            searchKeys: [SearchKeys],
            toolKeys: [ToolKeys],
            promptRepo: [PromptRepo],
            memoryArchive: [MemoryArchive],
            translationDic: [TranslationDic]
        ) {
            self.searchToolPreferences = searchToolPreferences
            self.scenarioDefaultModels = scenarioDefaultModels
            self.scenarioModelSources = scenarioModelSources
            self.trialChatPickerDisabledModelNames = trialChatPickerDisabledModelNames
            self.trial = trial
            self.trialModelPolicy = trialModelPolicy
            self.searchKeys = searchKeys
            self.toolKeys = toolKeys
            self.promptRepo = promptRepo
            self.memoryArchive = memoryArchive
            self.translationDic = translationDic
        }

        enum CodingKeys: String, CodingKey {
            case searchToolPreferences
            case userInfo
            case scenarioDefaultModels
            case scenarioModelSources
            case trialChatPickerDisabledModelNames
            case trial
            case trialModelPolicy
            case searchKeys
            case toolKeys
            case promptRepo
            case memoryArchive
            case translationDic
        }

        enum LegacyUserInfoKeys: String, CodingKey {
            case useKnowledge
            case knowledgeCount
            case knowledgeSimilarity
            case useSearch
            case bilingualSearch
            case searchCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let direct = try container.decodeIfPresent(AISearchToolPreferences.self, forKey: .searchToolPreferences) {
                searchToolPreferences = direct
            } else if container.contains(.userInfo),
                      let legacy = try? container.nestedContainer(keyedBy: LegacyUserInfoKeys.self, forKey: .userInfo)
            {
                searchToolPreferences = AISearchToolPreferences(
                    useKnowledge: try legacy.decodeIfPresent(Bool.self, forKey: .useKnowledge) ?? AISettingsDefaults.searchToolPreferences.useKnowledge,
                    knowledgeCount: try legacy.decodeIfPresent(Int.self, forKey: .knowledgeCount) ?? AISettingsDefaults.searchToolPreferences.knowledgeCount,
                    knowledgeSimilarity: try legacy.decodeIfPresent(Double.self, forKey: .knowledgeSimilarity) ?? AISettingsDefaults.searchToolPreferences.knowledgeSimilarity,
                    useSearch: try legacy.decodeIfPresent(Bool.self, forKey: .useSearch) ?? AISettingsDefaults.searchToolPreferences.useSearch,
                    bilingualSearch: try legacy.decodeIfPresent(Bool.self, forKey: .bilingualSearch) ?? AISettingsDefaults.searchToolPreferences.bilingualSearch,
                    searchCount: try legacy.decodeIfPresent(Int.self, forKey: .searchCount) ?? AISettingsDefaults.searchToolPreferences.searchCount
                )
            } else {
                searchToolPreferences = AISettingsDefaults.searchToolPreferences
            }

            scenarioDefaultModels = try container.decodeIfPresent([String: String].self, forKey: .scenarioDefaultModels) ?? [:]
            scenarioModelSources = try container.decodeIfPresent([String: AIModelSelectionSource].self, forKey: .scenarioModelSources) ?? [:]
            trialChatPickerDisabledModelNames = try container.decodeIfPresent([String].self, forKey: .trialChatPickerDisabledModelNames) ?? []
            trial = try container.decodeIfPresent(AITrialState.self, forKey: .trial) ?? .inactive
            trialModelPolicy = try container.decodeIfPresent([AITrialModelPolicyItem].self, forKey: .trialModelPolicy) ?? []
            searchKeys = try container.decodeIfPresent([SearchKeys].self, forKey: .searchKeys) ?? AISettingsDefaults.searchKeys
            toolKeys = try container.decodeIfPresent([ToolKeys].self, forKey: .toolKeys) ?? AISettingsDefaults.toolKeys
            promptRepo = try container.decodeIfPresent([PromptRepo].self, forKey: .promptRepo) ?? AISettingsDefaults.promptRepo
            memoryArchive = try container.decodeIfPresent([MemoryArchive].self, forKey: .memoryArchive) ?? AISettingsDefaults.memoryArchive
            translationDic = try container.decodeIfPresent([TranslationDic].self, forKey: .translationDic) ?? AISettingsDefaults.translationDic
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(searchToolPreferences, forKey: .searchToolPreferences)
            try container.encode(scenarioDefaultModels, forKey: .scenarioDefaultModels)
            try container.encode(scenarioModelSources, forKey: .scenarioModelSources)
            try container.encode(trialChatPickerDisabledModelNames, forKey: .trialChatPickerDisabledModelNames)
            try container.encode(trial, forKey: .trial)
            try container.encode(trialModelPolicy, forKey: .trialModelPolicy)
            try container.encode(searchKeys, forKey: .searchKeys)
            try container.encode(toolKeys, forKey: .toolKeys)
            try container.encode(promptRepo, forKey: .promptRepo)
            try container.encode(memoryArchive, forKey: .memoryArchive)
            try container.encode(translationDic, forKey: .translationDic)
        }
    }

    /// 从当前快照提取偏好载荷（字段与 `PreferencesPayload` 一致）。
    var preferencesPayload: PreferencesPayload {
        PreferencesPayload(
            searchToolPreferences: searchToolPreferences,
            scenarioDefaultModels: scenarioDefaultModels,
            scenarioModelSources: scenarioModelSources,
            trialChatPickerDisabledModelNames: trialChatPickerDisabledModelNames,
            trial: trial,
            trialModelPolicy: trialModelPolicy,
            searchKeys: searchKeys,
            toolKeys: toolKeys,
            promptRepo: promptRepo,
            memoryArchive: memoryArchive,
            translationDic: translationDic
        )
    }

    /// 用 Core Data 中的目录数据与已解码的偏好载荷组装完整快照。
    init(allModels: [AllModels], apiKeys: [APIKeys], smallTasks: [SmallTask] = [], preferences: PreferencesPayload) {
        self.init(
            allModels: allModels,
            apiKeys: apiKeys,
            smallTasks: smallTasks,
            searchToolPreferences: preferences.searchToolPreferences,
            scenarioDefaultModels: preferences.scenarioDefaultModels,
            scenarioModelSources: preferences.scenarioModelSources,
            trialChatPickerDisabledModelNames: preferences.trialChatPickerDisabledModelNames,
            trial: preferences.trial,
            trialModelPolicy: preferences.trialModelPolicy,
            searchKeys: preferences.searchKeys,
            toolKeys: preferences.toolKeys,
            promptRepo: preferences.promptRepo,
            memoryArchive: preferences.memoryArchive,
            translationDic: preferences.translationDic
        )
    }
}
