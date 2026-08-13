import Foundation

/// 按账号存于 Core Data 的 AI 设置快照（含 `allModels` / `apiKeys` / `smallTasks` / `promptRepo`）。
/// 已登录冷启动：`AppBootstrapper.bootstrapIfNeeded(for:)` 以 `UserSession.accountID` 调用 `AIConfigCenter.prewarm` 写入运行时缓存；设置页 `AISettingsViewModel` 应传入同一 `ownerAccountID` 加载目录，避免依赖会话快照解析顺序。
nonisolated struct AISettingsSnapshot: Codable, Equatable, Sendable {
    var allModels: [AllModels]
    var scenarioBindings: [AIScenarioModelBinding]
    var apiKeys: [APIKeys]
    var smallTasks: [SmallTask]
    /// 检索与知识相关本地偏好。
    var searchToolPreferences: AISearchToolPreferences
    /// 天气工具相关本地偏好。
    var weatherToolPreferences: AIWeatherToolPreferences
    /// 本地搜索配置版本；仅用于客户端内缓存失效、审计与工具消费，不参与服务端同步。
    var searchConfigRevision: SearchRuntimeConfigRevision
    /// 本地天气配置版本；仅用于客户端内缓存失效、审计与工具消费，不参与服务端同步。
    var weatherConfigRevision: WeatherRuntimeConfigRevision
    /// Chat 对话外观偏好。禁止与 DeepTutorChat 共用字段。
    var chatConversationAppearance: ChatConversationAppearancePreferences
    /// Chat 会话 UI 架构偏好。默认 UIKit，SwiftUI 入口完全独立于 DeepTutorChat。
    var chatConversationUIPreferences: ChatConversationUIPreferences
    /// Chat 工具交互展示偏好：成员选择、用户问答可分别选择 Sheet 或会话卡片。
    var chatToolInteractionPreferences: ChatToolInteractionPreferences
    /// 敏感工具结果发送给模型前的授权策略；按账号持久化。
    var toolModelEgressConsentPreferences: ToolModelEgressConsentPreferences
    /// Chat 会话默认启动偏好。
    var chatComposerStartupPreferences: ChatComposerStartupPreferences
    /// DeepTutorChat 对话外观偏好。禁止与 Chat 共用字段。
    var deepTutorConversationAppearance: DeepTutorConversationAppearancePreferences
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
        scenarioBindings: [AIScenarioModelBinding] = [],
        apiKeys: [APIKeys],
        smallTasks: [SmallTask] = [],
        searchToolPreferences: AISearchToolPreferences = AISettingsDefaults.searchToolPreferences,
        weatherToolPreferences: AIWeatherToolPreferences = AISettingsDefaults.weatherToolPreferences,
        searchConfigRevision: SearchRuntimeConfigRevision = SearchRuntimeConfigRevision(),
        weatherConfigRevision: WeatherRuntimeConfigRevision = WeatherRuntimeConfigRevision(),
        chatConversationAppearance: ChatConversationAppearancePreferences = .default,
        chatConversationUIPreferences: ChatConversationUIPreferences = .default,
        chatToolInteractionPreferences: ChatToolInteractionPreferences = .default,
        toolModelEgressConsentPreferences: ToolModelEgressConsentPreferences = .default,
        chatComposerStartupPreferences: ChatComposerStartupPreferences = .default,
        deepTutorConversationAppearance: DeepTutorConversationAppearancePreferences = .default,
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
        self.scenarioBindings = scenarioBindings
        self.apiKeys = apiKeys
        self.smallTasks = smallTasks
        self.searchToolPreferences = searchToolPreferences
        self.weatherToolPreferences = weatherToolPreferences
        self.searchConfigRevision = searchConfigRevision
        self.weatherConfigRevision = weatherConfigRevision
        self.chatConversationAppearance = chatConversationAppearance
        self.chatConversationUIPreferences = chatConversationUIPreferences
        self.chatToolInteractionPreferences = chatToolInteractionPreferences
        self.toolModelEgressConsentPreferences = toolModelEgressConsentPreferences
        self.chatComposerStartupPreferences = chatComposerStartupPreferences
        self.deepTutorConversationAppearance = deepTutorConversationAppearance
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
        scenarioBindings: [],
        apiKeys: [],
        smallTasks: [],
        searchToolPreferences: AISettingsDefaults.searchToolPreferences,
        weatherToolPreferences: AISettingsDefaults.weatherToolPreferences,
        searchConfigRevision: SearchRuntimeConfigRevision(),
        weatherConfigRevision: WeatherRuntimeConfigRevision(),
        chatConversationAppearance: .default,
        chatConversationUIPreferences: .default,
        chatToolInteractionPreferences: .default,
        toolModelEgressConsentPreferences: .default,
        chatComposerStartupPreferences: .default,
        deepTutorConversationAppearance: .default,
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
        scenarioBindings
            .first { $0.scenario == scenario.rawValue && $0.isActive && $0.isDefault }
            .flatMap { binding in allModels.first { $0.id == binding.modelID }?.name }
    }

    func scenarioModelSource(for scenario: AIScenario) -> AIModelSelectionSource {
        scenarioModelSources[scenario.rawValue] ?? .localKey
    }

    mutating func setScenarioDefaultModelName(_ modelName: String?, for scenario: AIScenario) {
        let trimmed = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false,
              let model = allModels.first(where: { $0.name == trimmed })
        else { return }
        for index in scenarioBindings.indices where scenarioBindings[index].scenario == scenario.rawValue {
            scenarioBindings[index].isDefault = scenarioBindings[index].modelID == model.id
            scenarioBindings[index].updatedAt = Date()
        }
    }

    mutating func setScenarioModelSource(_ source: AIModelSelectionSource, for scenario: AIScenario) {
        scenarioModelSources[scenario.rawValue] = source
    }

    mutating func refreshSearchConfigRevision(previous: AISettingsSnapshot?) {
        normalizeSearchProviderSelection()
        let hash = SearchRuntimeConfigResolver.normalizedHash(
            preferences: searchToolPreferences,
            searchKeys: searchKeys
        )
        let previousRevision = previous?.searchConfigRevision ?? searchConfigRevision
        guard hash != previousRevision.preferencesHash else {
            searchConfigRevision = previousRevision
            return
        }

        let activeID = searchKeys.first(where: { $0.isUsing })?.id
        searchConfigRevision = SearchRuntimeConfigRevision(
            schemaVersion: SearchRuntimeConfigRevision.schemaVersion,
            localRevision: max(1, previousRevision.localRevision + 1),
            updatedAt: Date(),
            activeSearchKeyID: activeID,
            preferencesHash: hash
        )
    }

    mutating func refreshWeatherConfigRevision(previous: AISettingsSnapshot?) {
        normalizeWeatherProviderSelection()
        let hash = WeatherRuntimeConfigResolver.normalizedHash(
            preferences: weatherToolPreferences,
            toolKeys: toolKeys
        )
        let previousRevision = previous?.weatherConfigRevision ?? weatherConfigRevision
        guard hash != previousRevision.preferencesHash else {
            weatherConfigRevision = previousRevision
            return
        }

        let activeID = toolKeys.first(where: { $0.toolClass.lowercased() == "weather" && $0.isUsing })?.id
        weatherConfigRevision = WeatherRuntimeConfigRevision(
            schemaVersion: WeatherRuntimeConfigRevision.schemaVersion,
            localRevision: max(1, previousRevision.localRevision + 1),
            updatedAt: Date(),
            activeWeatherKeyID: activeID,
            preferencesHash: hash
        )
    }

    mutating func normalizeWeatherProviderSelection() {
        let activeIndices = toolKeys.enumerated()
            .filter { $0.element.toolClass.lowercased() == "weather" && $0.element.isUsing }
            .map(\.offset)
        guard activeIndices.count > 1 else { return }
        let keep = activeIndices.max { toolKeys[$0].timestamp < toolKeys[$1].timestamp }
        for index in toolKeys.indices where index != keep {
            if toolKeys[index].toolClass.lowercased() == "weather" {
                toolKeys[index].isUsing = false
            }
        }
    }

    mutating func normalizeSearchProviderSelection() {
        let activeIDs = searchKeys
            .enumerated()
            .filter { $0.element.isUsing }
            .map(\.offset)
        guard activeIDs.count > 1 else { return }
        let keep = activeIDs
            .max {
                let lhs = searchKeys[$0]
                let rhs = searchKeys[$1]
                if lhs.priority == rhs.priority {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.priority < rhs.priority
            }
        for index in searchKeys.indices where index != keep {
            searchKeys[index].isUsing = false
        }
    }
}

// MARK: - 偏好持久化载荷（与快照轻量偏好字段一致）

nonisolated extension AISettingsSnapshot {
    /// 供账号级 UserDefaults 序列化；模型目录、小任务、提示词库等可维护数据以 Core Data 为准。
    /// 仓储层只对该类型做 `JSONEncoder` / `JSONDecoder`，避免重复结构体与手写映射。
    nonisolated struct PreferencesPayload: Codable, Equatable, Sendable {
        var searchToolPreferences: AISearchToolPreferences
        var weatherToolPreferences: AIWeatherToolPreferences
        var searchConfigRevision: SearchRuntimeConfigRevision
        var weatherConfigRevision: WeatherRuntimeConfigRevision
        var chatConversationAppearance: ChatConversationAppearancePreferences
        var chatConversationUIPreferences: ChatConversationUIPreferences
        var chatToolInteractionPreferences: ChatToolInteractionPreferences
        var toolModelEgressConsentPreferences: ToolModelEgressConsentPreferences
        var chatComposerStartupPreferences: ChatComposerStartupPreferences
        var deepTutorConversationAppearance: DeepTutorConversationAppearancePreferences
        var scenarioModelSources: [String: AIModelSelectionSource]
        var trialChatPickerDisabledModelNames: [String]
        var trial: AITrialState
        var trialModelPolicy: [AITrialModelPolicyItem]
        var searchKeys: [SearchKeys]
        var toolKeys: [ToolKeys]
        var memoryArchive: [MemoryArchive]
        var translationDic: [TranslationDic]

        static let `default` = PreferencesPayload(
            searchToolPreferences: AISettingsDefaults.searchToolPreferences,
            weatherToolPreferences: AISettingsDefaults.weatherToolPreferences,
            searchConfigRevision: SearchRuntimeConfigRevision(),
            weatherConfigRevision: WeatherRuntimeConfigRevision(),
            chatConversationAppearance: .default,
            chatConversationUIPreferences: .default,
            chatToolInteractionPreferences: .default,
            toolModelEgressConsentPreferences: .default,
            chatComposerStartupPreferences: .default,
            deepTutorConversationAppearance: .default,
            scenarioModelSources: [:],
            trialChatPickerDisabledModelNames: [],
            trial: .inactive,
            trialModelPolicy: [],
            searchKeys: AISettingsDefaults.searchKeys,
            toolKeys: AISettingsDefaults.toolKeys,
            memoryArchive: AISettingsDefaults.memoryArchive,
            translationDic: AISettingsDefaults.translationDic
        )

        init(
            searchToolPreferences: AISearchToolPreferences,
            weatherToolPreferences: AIWeatherToolPreferences,
            searchConfigRevision: SearchRuntimeConfigRevision,
            weatherConfigRevision: WeatherRuntimeConfigRevision,
            chatConversationAppearance: ChatConversationAppearancePreferences,
            chatConversationUIPreferences: ChatConversationUIPreferences,
            chatToolInteractionPreferences: ChatToolInteractionPreferences,
            toolModelEgressConsentPreferences: ToolModelEgressConsentPreferences,
            chatComposerStartupPreferences: ChatComposerStartupPreferences,
            deepTutorConversationAppearance: DeepTutorConversationAppearancePreferences,
            scenarioModelSources: [String: AIModelSelectionSource],
            trialChatPickerDisabledModelNames: [String],
            trial: AITrialState,
            trialModelPolicy: [AITrialModelPolicyItem],
            searchKeys: [SearchKeys],
            toolKeys: [ToolKeys],
            memoryArchive: [MemoryArchive],
            translationDic: [TranslationDic]
        ) {
            self.searchToolPreferences = searchToolPreferences
            self.weatherToolPreferences = weatherToolPreferences
            self.searchConfigRevision = searchConfigRevision
            self.weatherConfigRevision = weatherConfigRevision
            self.chatConversationAppearance = chatConversationAppearance
            self.chatConversationUIPreferences = chatConversationUIPreferences
            self.chatToolInteractionPreferences = chatToolInteractionPreferences
            self.toolModelEgressConsentPreferences = toolModelEgressConsentPreferences
            self.chatComposerStartupPreferences = chatComposerStartupPreferences
            self.deepTutorConversationAppearance = deepTutorConversationAppearance
            self.scenarioModelSources = scenarioModelSources
            self.trialChatPickerDisabledModelNames = trialChatPickerDisabledModelNames
            self.trial = trial
            self.trialModelPolicy = trialModelPolicy
            self.searchKeys = searchKeys
            self.toolKeys = toolKeys
            self.memoryArchive = memoryArchive
            self.translationDic = translationDic
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
            let container = try decoder.container(keyedBy: CodableKey.self)

            func decodeSafely<T: Decodable>(
                _ type: T.Type,
                forKey key: CodableKey,
                default defaultValue: @autoclosure () -> T
            ) -> T {
                do {
                    return try container.decodeIfPresent(type, forKey: key) ?? defaultValue()
                } catch {
                    return defaultValue()
                }
            }

            if let direct = try container.decodeIfPresent(AISearchToolPreferences.self, forKey: .key("searchToolPreferences")) {
                searchToolPreferences = direct
            } else if container.contains(.key("userInfo")),
                      let legacy = try? container.nestedContainer(keyedBy: LegacyUserInfoKeys.self, forKey: .key("userInfo"))
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
            weatherToolPreferences = decodeSafely(
                AIWeatherToolPreferences.self,
                forKey: .key("weatherToolPreferences"),
                default: AISettingsDefaults.weatherToolPreferences
            )
            searchConfigRevision = decodeSafely(
                SearchRuntimeConfigRevision.self,
                forKey: .key("searchConfigRevision"),
                default: SearchRuntimeConfigRevision()
            )
            weatherConfigRevision = decodeSafely(
                WeatherRuntimeConfigRevision.self,
                forKey: .key("weatherConfigRevision"),
                default: WeatherRuntimeConfigRevision()
            )
            chatConversationAppearance = decodeSafely(
                ChatConversationAppearancePreferences.self,
                forKey: .key("chatConversationAppearance"),
                default: .default
            )
            chatConversationUIPreferences = decodeSafely(
                ChatConversationUIPreferences.self,
                forKey: .key("chatConversationUIPreferences"),
                default: .default
            )
            chatToolInteractionPreferences = decodeSafely(
                ChatToolInteractionPreferences.self,
                forKey: .key("chatToolInteractionPreferences"),
                default: .default
            )
            toolModelEgressConsentPreferences = decodeSafely(
                ToolModelEgressConsentPreferences.self,
                forKey: .key("toolModelEgressConsentPreferences"),
                default: .default
            )
            chatComposerStartupPreferences = decodeSafely(
                ChatComposerStartupPreferences.self,
                forKey: .key("chatComposerStartupPreferences"),
                default: .default
            )
            deepTutorConversationAppearance = decodeSafely(
                DeepTutorConversationAppearancePreferences.self,
                forKey: .key("deepTutorConversationAppearance"),
                default: .default
            )

            scenarioModelSources = decodeSafely(
                [String: AIModelSelectionSource].self,
                forKey: .key("scenarioModelSources"),
                default: [:]
            )
            trialChatPickerDisabledModelNames = decodeSafely(
                [String].self,
                forKey: .key("trialChatPickerDisabledModelNames"),
                default: []
            )
            trial = decodeSafely(
                AITrialState.self,
                forKey: .key("trial"),
                default: .inactive
            )
            trialModelPolicy = decodeSafely(
                [AITrialModelPolicyItem].self,
                forKey: .key("trialModelPolicy"),
                default: []
            )
            searchKeys = decodeSafely(
                [SearchKeys].self,
                forKey: .key("searchKeys"),
                default: AISettingsDefaults.searchKeys
            )
            toolKeys = decodeSafely(
                [ToolKeys].self,
                forKey: .key("toolKeys"),
                default: AISettingsDefaults.toolKeys
            )
            memoryArchive = decodeSafely(
                [MemoryArchive].self,
                forKey: .key("memoryArchive"),
                default: AISettingsDefaults.memoryArchive
            )
            translationDic = decodeSafely(
                [TranslationDic].self,
                forKey: .key("translationDic"),
                default: AISettingsDefaults.translationDic
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKey.self)
            try container.encode(searchToolPreferences, forKey: .key("searchToolPreferences"))
            try container.encode(weatherToolPreferences, forKey: .key("weatherToolPreferences"))
            try container.encode(searchConfigRevision, forKey: .key("searchConfigRevision"))
            try container.encode(weatherConfigRevision, forKey: .key("weatherConfigRevision"))
            try container.encode(chatConversationAppearance, forKey: .key("chatConversationAppearance"))
            try container.encode(chatConversationUIPreferences, forKey: .key("chatConversationUIPreferences"))
            try container.encode(chatToolInteractionPreferences, forKey: .key("chatToolInteractionPreferences"))
            try container.encode(toolModelEgressConsentPreferences, forKey: .key("toolModelEgressConsentPreferences"))
            try container.encode(chatComposerStartupPreferences, forKey: .key("chatComposerStartupPreferences"))
            try container.encode(deepTutorConversationAppearance, forKey: .key("deepTutorConversationAppearance"))
            try container.encode(scenarioModelSources, forKey: .key("scenarioModelSources"))
            try container.encode(trialChatPickerDisabledModelNames, forKey: .key("trialChatPickerDisabledModelNames"))
            try container.encode(trial, forKey: .key("trial"))
            try container.encode(trialModelPolicy, forKey: .key("trialModelPolicy"))
            try container.encode(searchKeys, forKey: .key("searchKeys"))
            try container.encode(toolKeys, forKey: .key("toolKeys"))
            try container.encode(memoryArchive, forKey: .key("memoryArchive"))
            try container.encode(translationDic, forKey: .key("translationDic"))
        }
    }

    /// 从当前快照提取轻量偏好载荷。`promptRepo` 完全由 Core Data 持久化，不进入 UserDefaults。
    var preferencesPayload: PreferencesPayload {
        PreferencesPayload(
            searchToolPreferences: searchToolPreferences,
            weatherToolPreferences: weatherToolPreferences,
            searchConfigRevision: searchConfigRevision,
            weatherConfigRevision: weatherConfigRevision,
            chatConversationAppearance: chatConversationAppearance,
            chatConversationUIPreferences: chatConversationUIPreferences,
            chatToolInteractionPreferences: chatToolInteractionPreferences,
            toolModelEgressConsentPreferences: toolModelEgressConsentPreferences,
            chatComposerStartupPreferences: chatComposerStartupPreferences,
            deepTutorConversationAppearance: deepTutorConversationAppearance,
            scenarioModelSources: scenarioModelSources,
            trialChatPickerDisabledModelNames: trialChatPickerDisabledModelNames,
            trial: trial,
            trialModelPolicy: trialModelPolicy,
            searchKeys: searchKeys,
            toolKeys: toolKeys,
            memoryArchive: memoryArchive,
            translationDic: translationDic
        )
    }

    /// 用 Core Data 中的目录数据与已解码的偏好载荷组装完整快照。
    init(
        allModels: [AllModels],
        scenarioBindings: [AIScenarioModelBinding] = [],
        apiKeys: [APIKeys],
        smallTasks: [SmallTask] = [],
        promptRepo: [PromptRepo],
        preferences: PreferencesPayload
    ) {
        self.init(
            allModels: allModels,
            scenarioBindings: scenarioBindings,
            apiKeys: apiKeys,
            smallTasks: smallTasks,
            searchToolPreferences: preferences.searchToolPreferences,
            weatherToolPreferences: preferences.weatherToolPreferences,
            searchConfigRevision: preferences.searchConfigRevision,
            weatherConfigRevision: preferences.weatherConfigRevision,
            chatConversationAppearance: preferences.chatConversationAppearance,
            chatConversationUIPreferences: preferences.chatConversationUIPreferences,
            chatToolInteractionPreferences: preferences.chatToolInteractionPreferences,
            toolModelEgressConsentPreferences: preferences.toolModelEgressConsentPreferences,
            chatComposerStartupPreferences: preferences.chatComposerStartupPreferences,
            deepTutorConversationAppearance: preferences.deepTutorConversationAppearance,
            scenarioModelSources: preferences.scenarioModelSources,
            trialChatPickerDisabledModelNames: preferences.trialChatPickerDisabledModelNames,
            trial: preferences.trial,
            trialModelPolicy: preferences.trialModelPolicy,
            searchKeys: preferences.searchKeys,
            toolKeys: preferences.toolKeys,
            promptRepo: promptRepo,
            memoryArchive: preferences.memoryArchive,
            translationDic: preferences.translationDic
        )
    }
}
