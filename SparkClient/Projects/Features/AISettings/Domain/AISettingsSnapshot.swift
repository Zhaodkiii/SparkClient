import Foundation

/// 按账号存于 Core Data 的 AI 设置快照（含 `allModels` / `apiKeys`）。
/// 已登录冷启动：`AppBootstrapper.bootstrapIfNeeded(for:)` 以 `UserSession.accountID` 调用 `AIConfigCenter.prewarm` 写入运行时缓存；设置页 `AISettingsViewModel` 应传入同一 `ownerAccountID` 加载目录，避免依赖会话快照解析顺序。
struct AISettingsSnapshot: Codable, Equatable, Sendable {
    var allModels: [AllModels]
    var apiKeys: [APIKeys]
    /// 用户偏好与其它本地选项（嵌入模型名、各场景来源等）。
    var userInfo: UserInfo
    /// 场景级默认模型（`AIScenario.rawValue` -> 模型 `name`）。
    var scenarioDefaultModels: [String: String]
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
        userInfo: UserInfo = AISettingsDefaults.userInfo,
        scenarioDefaultModels: [String: String] = [:],
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
        self.userInfo = userInfo
        self.scenarioDefaultModels = scenarioDefaultModels
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
        userInfo: AISettingsDefaults.userInfo,
        scenarioDefaultModels: [:],
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
}

// MARK: - 偏好持久化载荷（与快照非目录字段一致）

extension AISettingsSnapshot {
    /// 与 `AISettingsSnapshot` 中除 `allModels` / `apiKeys` 外的字段一一对应，供账号级 UserDefaults 序列化；
    /// 仓储层只对该类型做 `JSONEncoder` / `JSONDecoder`，避免重复结构体与手写映射。
    struct PreferencesPayload: Codable, Equatable, Sendable {
        var userInfo: UserInfo
        var scenarioDefaultModels: [String: String]
        var trialChatPickerDisabledModelNames: [String]
        var trial: AITrialState
        var trialModelPolicy: [AITrialModelPolicyItem]
        var searchKeys: [SearchKeys]
        var toolKeys: [ToolKeys]
        var promptRepo: [PromptRepo]
        var memoryArchive: [MemoryArchive]
        var translationDic: [TranslationDic]

        static let `default` = PreferencesPayload(
            userInfo: AISettingsDefaults.userInfo,
            scenarioDefaultModels: [:],
            trialChatPickerDisabledModelNames: [],
            trial: .inactive,
            trialModelPolicy: [],
            searchKeys: AISettingsDefaults.searchKeys,
            toolKeys: AISettingsDefaults.toolKeys,
            promptRepo: AISettingsDefaults.promptRepo,
            memoryArchive: AISettingsDefaults.memoryArchive,
            translationDic: AISettingsDefaults.translationDic
        )
    }

    /// 从当前快照提取偏好载荷（字段与 `PreferencesPayload` 一致）。
    var preferencesPayload: PreferencesPayload {
        PreferencesPayload(
            userInfo: userInfo,
            scenarioDefaultModels: scenarioDefaultModels,
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
    init(allModels: [AllModels], apiKeys: [APIKeys], preferences: PreferencesPayload) {
        self.init(
            allModels: allModels,
            apiKeys: apiKeys,
            userInfo: preferences.userInfo,
            scenarioDefaultModels: preferences.scenarioDefaultModels,
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
