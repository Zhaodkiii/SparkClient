import Foundation

/// AI 设置默认仓储实现类
/// 负责：配置加载 / 保存 / 模型预置 / 密钥迁移与安全存储 / 数据脱敏持久化
final class DefaultAISettingsRepository: AISettingsRepository, @unchecked Sendable {

    // MARK: - 存储 Key 定义
    private enum Keys {
        /// 设置快照存储 Key（带版本号）
        static let snapshot = "spark.ai.settings.snapshot.v1"
    }

    // MARK: - 属性
    /// 偏好设置存储（普通配置）
    private let userDefaults: UserDefaults
    /// 密钥安全存储（钥匙串）
    private let secretStore: any AISettingsSecretStore
    /// JSON 编码器
    private let encoder = JSONEncoder()
    /// 日志工具
    private let logger: Logger

    // MARK: - 初始化
    init(
        userDefaults: UserDefaults = .standard,
        secretStore: any AISettingsSecretStore = KeychainAISettingsSecretStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
        self.logger = logger
    }

    // MARK: - 加载设置快照（对外）
    /// 加载完整的 AI 设置快照
    /// 包含：迁移旧密钥 → 预加载预置数据 → 填充密钥 → 持久化
    func loadSnapshot() async -> AISettingsSnapshot {
        var loaded = loadPersistedSnapshot() ?? .default
        var migrated = false

        // 1. 迁移历史明文密钥到安全存储
        if migrateLegacySecretsToStore(snapshot: &loaded) {
            migrated = true
        }

        // 2. 预加载缺失的系统预置数据（模型、密钥、提示词等）
        loaded = preloadIfNeeded(snapshot: loaded)

        // 3. 从安全存储中回填密钥到内存
        hydrateSecrets(snapshot: &loaded)

        // 4. 若发生迁移或首次初始化，则重新持久化
        if migrated || userDefaults.data(forKey: Keys.snapshot) == nil {
            do {
                try persist(snapshot: loaded)
                logger.info("AI 设置已完成初始化", category: "ai_settings")
            } catch {
                logger.warning("AI 设置初始化持久化失败：\(error.localizedDescription)", category: "ai_settings")
            }
        }

        return loaded
    }

    // MARK: - 保存设置快照（对外）
    /// 保存设置快照（自动脱敏密钥并同步到安全存储）
    func save(snapshot: AISettingsSnapshot) async throws {
        try persist(snapshot: snapshot)
        logger.info("AI 设置快照已保存", category: "ai_settings")
    }

    // MARK: - 持久化（内部）
    /// 持久化快照：先同步密钥 → 脱敏 → 再保存到 UserDefaults
    private func persist(snapshot: AISettingsSnapshot) throws {
        var sanitized = snapshot
        syncSecretsToStoreAndSanitize(snapshot: &sanitized)
        let data = try encoder.encode(sanitized)
        userDefaults.set(data, forKey: Keys.snapshot)
    }

    /// 从本地加载已持久化的快照
    private func loadPersistedSnapshot() -> AISettingsSnapshot? {
        guard let data = userDefaults.data(forKey: Keys.snapshot) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(AISettingsSnapshot.self, from: data)
    }

    // MARK: - 预加载（系统预置数据）
    /// 统一入口：预加载所有缺失的系统配置
    private func preloadIfNeeded(snapshot: AISettingsSnapshot) -> AISettingsSnapshot {
        var value = snapshot
        preloadModelDataIfNeeded(snapshot: &value)
        preloadAPIKeysIfNeeded(snapshot: &value)
        preloadSearchKeysIfNeeded(snapshot: &value)
        preloadToolKeysIfNeeded(snapshot: &value)
        preloadPromptIfNeeded(snapshot: &value)
        preloadUserInfoIfNeeded(snapshot: &value)
        return value
    }

    // MARK: - 模型预加载与合并
    /// 预加载系统模型，合并用户自定义模型，去重、排序
    private func preloadModelDataIfNeeded(snapshot: inout AISettingsSnapshot) {
        let predefinedModels = AISettingsSeedCatalog.getModelList()
        let predefinedModelKeys = Set(predefinedModels.map { dedupKey(name: $0.name, fallbackID: $0.id) })
        let referencedModelNames = referencedModelNames(in: snapshot)

        var modelMap: [String: AllModels] = [:]
        for model in snapshot.allModels {
            let key = dedupKey(name: model.name, fallbackID: model.id)
            // 过滤已废弃的系统模型
            // 但如果该模型仍被场景配置/试用策略/远端场景模型引用，则必须保留。
            if model.source == .system,
               !predefinedModelKeys.contains(key),
               !referencedModelNames.contains(model.name) {
                continue
            }
            // 存在则合并，不存在则直接存入
            if let existing = modelMap[key] {
                modelMap[key] = mergeModel(existing: existing, incoming: model)
            } else {
                modelMap[key] = model
            }
        }

        // 合并系统预置模型
        for preset in predefinedModels {
            let key = dedupKey(name: preset.name, fallbackID: preset.id)
            if let existing = modelMap[key] {
                modelMap[key] = mergeModel(existing: existing, incoming: preset)
            } else {
                modelMap[key] = preset
            }
        }

        // 排序：按 position → 名称
        snapshot.allModels = modelMap.values.sorted { lhs, rhs in
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            return dedupKey(name: lhs.name, fallbackID: lhs.id) < dedupKey(name: rhs.name, fallbackID: rhs.id)
        }
    }

    /// 收集当前快照中“正在被使用/可能被路由到”的模型名，避免预加载阶段误删系统模型。
    private func referencedModelNames(in snapshot: AISettingsSnapshot) -> Set<String> {
        var names = Set([
            snapshot.chat.model,
            snapshot.optimizationText.model,
            snapshot.optimizationVisual.model,
            snapshot.contextFolding.model,
            snapshot.router.model,
            snapshot.modelConfig.model,
            snapshot.reportInterpretation.model
        ].filter { !$0.isEmpty })

        names.formUnion(snapshot.scenarioSelectedModel.values.filter { !$0.isEmpty })
        names.formUnion(snapshot.trialModelPolicy.map(\.config.model).filter { !$0.isEmpty })

        if let bundles = snapshot.scenarioRemoteBundles {
            for scenario in AIScenario.allCases {
                let rows = bundles.bundle(for: scenario).models
                for row in rows where row.model.isEmpty == false {
                    names.insert(row.model)
                }
            }
        }
        return names
    }

    /// 模型合并策略：自定义 > 系统；保留用户修改，合并能力开关
    private func mergeModel(existing: AllModels, incoming: AllModels) -> AllModels {
        if existing.source == .custom, incoming.source == .system {
            var merged = existing
            merged.supportsSearch = incoming.supportsSearch || existing.supportsSearch
            merged.supportsMultimodal = incoming.supportsMultimodal || existing.supportsMultimodal
            merged.supportsReasoning = incoming.supportsReasoning || existing.supportsReasoning
            merged.supportsToolUse = incoming.supportsToolUse || existing.supportsToolUse
            merged.supportsVoiceGen = incoming.supportsVoiceGen || existing.supportsVoiceGen
            merged.supportsImageGen = incoming.supportsImageGen || existing.supportsImageGen
            merged.priceTier = min(max(incoming.priceTier, 0), 3)
            merged.supportsText = incoming.supportsText || existing.supportsText
            merged.reasoningControllable = incoming.reasoningControllable || existing.reasoningControllable
            return merged
        }
        // 自定义配置优先
        if incoming.source == .custom {
            return incoming
        }
        return existing
    }

    // MARK: - API 密钥预加载
    private func preloadAPIKeysIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaults = AISettingsSeedCatalog.getAPIKeyList()
        let knownSystemKeys = Set(defaults.map { dedupKey(name: $0.name, fallbackID: $0.id) })

        snapshot.apiKeys = mergeRecordCollection(
            existing: snapshot.apiKeys.filter { record in
                if record.source == .system {
                    return knownSystemKeys.contains(dedupKey(name: record.name, fallbackID: record.id))
                }
                return true
            },
            defaults: defaults,
            key: { dedupKey(name: $0.name, fallbackID: $0.id) }
        ) { old, new in
            if old.source == .custom, new.source == .system { return old }
            if new.source == .custom { return new }
            if old.key.isEmpty, !new.key.isEmpty { return new }
            return old
        }
    }

    // MARK: - 搜索密钥预加载
    private func preloadSearchKeysIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaults = AISettingsSeedCatalog.getSearchKeyList()
        let knownSystemKeys = Set(defaults.map { dedupKey(name: $0.name, fallbackID: $0.id) })

        snapshot.searchKeys = mergeRecordCollection(
            existing: snapshot.searchKeys.filter { record in
                if record.source == .system {
                    return knownSystemKeys.contains(dedupKey(name: record.name, fallbackID: record.id))
                }
                return true
            },
            defaults: defaults,
            key: { dedupKey(name: $0.name, fallbackID: $0.id) }
        ) { old, new in
            if old.source == .custom, new.source == .system { return old }
            if new.source == .custom { return new }
            return old
        }
    }

    // MARK: - 工具密钥预加载
    private func preloadToolKeysIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaults = AISettingsSeedCatalog.getToolKeyList()
        let knownSystemKeys = Set(defaults.map { dedupKey(name: $0.name, fallbackID: $0.id) })

        snapshot.toolKeys = mergeRecordCollection(
            existing: snapshot.toolKeys.filter { record in
                if record.source == .system {
                    return knownSystemKeys.contains(dedupKey(name: record.name, fallbackID: record.id))
                }
                return true
            },
            defaults: defaults,
            key: { dedupKey(name: $0.name, fallbackID: $0.id) }
        ) { old, new in
            if old.source == .custom, new.source == .system { return old }
            if new.source == .custom { return new }
            return old
        }
    }

    // MARK: - 系统提示词预加载
    private func preloadPromptIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaultPrompts = AISettingsSeedCatalog.getPromptList()
        let defaultTitles = Set(defaultPrompts.map(\.title))
        var merged = snapshot.promptRepo
        for preset in defaultPrompts where !merged.contains(where: { $0.title == preset.title }) {
            merged.append(preset)
        }
        // 清理废弃的系统提示词
        snapshot.promptRepo = merged.filter { record in
            if record.isSystem {
                return defaultTitles.contains(record.title)
            }
            return true
        }
    }

    // MARK: - 用户默认信息预加载
    private func preloadUserInfoIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaultUserInfo = AISettingsSeedCatalog.getDefaultUserInfo()
        var userInfo = snapshot.userInfo

        if userInfo.chooseEmbeddingModel.isEmpty {
            userInfo.chooseEmbeddingModel = defaultUserInfo.chooseEmbeddingModel
        }
        if userInfo.optimizationTextModel.isEmpty {
            userInfo.optimizationTextModel = defaultUserInfo.optimizationTextModel
        }
        if userInfo.optimizationVisualModel.isEmpty {
            userInfo.optimizationVisualModel = defaultUserInfo.optimizationVisualModel
        }
        if userInfo.contextFoldingModel.isEmpty {
            userInfo.contextFoldingModel = defaultUserInfo.contextFoldingModel
        }
        if userInfo.routerModel.isEmpty {
            userInfo.routerModel = defaultUserInfo.routerModel
        }
        if userInfo.dataExtractionModel.isEmpty {
            userInfo.dataExtractionModel = defaultUserInfo.dataExtractionModel
        }
        if userInfo.reportInterpretationModel.isEmpty {
            userInfo.reportInterpretationModel = defaultUserInfo.reportInterpretationModel
        }
        if userInfo.maxToolSets <= 0 {
            userInfo.maxToolSets = defaultUserInfo.maxToolSets
        }
        if userInfo.textToSpeechModel.isEmpty {
            userInfo.textToSpeechModel = defaultUserInfo.textToSpeechModel
        }
        if userInfo.knowledgeCount <= 0 {
            userInfo.knowledgeCount = defaultUserInfo.knowledgeCount
        }
        if userInfo.searchCount <= 0 {
            userInfo.searchCount = defaultUserInfo.searchCount
        }
        if userInfo.knowledgeSimilarity <= 0 {
            userInfo.knowledgeSimilarity = defaultUserInfo.knowledgeSimilarity
        }

        snapshot.userInfo = userInfo
    }

    // MARK: - 通用集合合并工具
    /// 通用列表合并：去重 + 合并 + 排序
    private func mergeRecordCollection<T: Sendable>(
        existing: [T],
        defaults: [T],
        key: (T) -> String,
        merger: (T, T) -> T
    ) -> [T] {
        var map: [String: T] = [:]
        for item in existing {
            map[key(item)] = item
        }
        for preset in defaults {
            let itemKey = key(preset)
            if let old = map[itemKey] {
                map[itemKey] = merger(old, preset)
            } else {
                map[itemKey] = preset
            }
        }
        return map.values.sorted { key($0) < key($1) }
    }

    /// 生成去重 Key：名称小写，空则用 ID
    private func dedupKey(name: String, fallbackID: UUID) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "__id__\(fallbackID.uuidString.lowercased())"
        }
        return normalized
    }

    // MARK: - 密钥安全存储（迁移 / 填充 / 同步）
    /// 迁移旧版明文密钥到安全存储
    private func migrateLegacySecretsToStore(snapshot: inout AISettingsSnapshot) -> Bool {
        var changed = false

        // 场景 API Key 迁移
        changed = migrateScenarioSecret(snapshot: &snapshot.chat, scenario: .chat) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.optimizationText, scenario: .optimizationText) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.optimizationVisual, scenario: .optimizationVisual) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.contextFolding, scenario: .contextFolding) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.router, scenario: .router) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.modelConfig, scenario: .modelConfig) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.reportInterpretation, scenario: .reportInterpretation) || changed

        // API 密钥迁移
        for index in snapshot.apiKeys.indices {
            let secret = snapshot.apiKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else { continue }
            let account = secretAccount(
                namespace: "api",
                company: snapshot.apiKeys[index].company,
                name: snapshot.apiKeys[index].name,
                fallbackID: snapshot.apiKeys[index].id
            )
            secretStore.write(secret, account: account)
            snapshot.apiKeys[index].key = ""
            changed = true
        }

        // 搜索密钥迁移
        for index in snapshot.searchKeys.indices {
            let secret = snapshot.searchKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else { continue }
            let account = secretAccount(
                namespace: "search",
                company: snapshot.searchKeys[index].company,
                name: snapshot.searchKeys[index].name,
                fallbackID: snapshot.searchKeys[index].id
            )
            secretStore.write(secret, account: account)
            snapshot.searchKeys[index].key = ""
            changed = true
        }

        // 工具密钥迁移
        for index in snapshot.toolKeys.indices {
            let secret = snapshot.toolKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else { continue }
            let account = secretAccount(
                namespace: "tool",
                company: snapshot.toolKeys[index].company,
                name: snapshot.toolKeys[index].name,
                fallbackID: snapshot.toolKeys[index].id
            )
            secretStore.write(secret, account: account)
            snapshot.toolKeys[index].key = ""
            changed = true
        }

        return changed
    }

    /// 从安全存储回填密钥到内存快照
    private func hydrateSecrets(snapshot: inout AISettingsSnapshot) {
        snapshot.chat.apiKey = secretStore.read(account: scenarioSecretAccount(.chat))
        snapshot.optimizationText.apiKey = secretStore.read(account: scenarioSecretAccount(.optimizationText))
        snapshot.optimizationVisual.apiKey = secretStore.read(account: scenarioSecretAccount(.optimizationVisual))
        snapshot.contextFolding.apiKey = secretStore.read(account: scenarioSecretAccount(.contextFolding))
        snapshot.router.apiKey = secretStore.read(account: scenarioSecretAccount(.router))
        snapshot.modelConfig.apiKey = secretStore.read(account: scenarioSecretAccount(.modelConfig))
        snapshot.reportInterpretation.apiKey = secretStore.read(account: scenarioSecretAccount(.reportInterpretation))

        // 回填 API 密钥
        for index in snapshot.apiKeys.indices {
            let account = secretAccount(
                namespace: "api",
                company: snapshot.apiKeys[index].company,
                name: snapshot.apiKeys[index].name,
                fallbackID: snapshot.apiKeys[index].id
            )
            snapshot.apiKeys[index].key = secretStore.read(account: account) ?? ""
        }

        // 回填搜索密钥
        for index in snapshot.searchKeys.indices {
            let account = secretAccount(
                namespace: "search",
                company: snapshot.searchKeys[index].company,
                name: snapshot.searchKeys[index].name,
                fallbackID: snapshot.searchKeys[index].id
            )
            snapshot.searchKeys[index].key = secretStore.read(account: account) ?? ""
        }

        // 回填工具密钥
        for index in snapshot.toolKeys.indices {
            let account = secretAccount(
                namespace: "tool",
                company: snapshot.toolKeys[index].company,
                name: snapshot.toolKeys[index].name,
                fallbackID: snapshot.toolKeys[index].id
            )
            snapshot.toolKeys[index].key = secretStore.read(account: account) ?? ""
        }
    }

    /// 保存前同步密钥到安全存储，并清空快照中的明文密钥
    private func syncSecretsToStoreAndSanitize(snapshot: inout AISettingsSnapshot) {
        syncScenarioSecret(snapshot: &snapshot.chat, scenario: .chat)
        syncScenarioSecret(snapshot: &snapshot.optimizationText, scenario: .optimizationText)
        syncScenarioSecret(snapshot: &snapshot.optimizationVisual, scenario: .optimizationVisual)
        syncScenarioSecret(snapshot: &snapshot.contextFolding, scenario: .contextFolding)
        syncScenarioSecret(snapshot: &snapshot.router, scenario: .router)
        syncScenarioSecret(snapshot: &snapshot.modelConfig, scenario: .modelConfig)
        syncScenarioSecret(snapshot: &snapshot.reportInterpretation, scenario: .reportInterpretation)

        // API 密钥同步
        for index in snapshot.apiKeys.indices {
            let account = secretAccount(
                namespace: "api",
                company: snapshot.apiKeys[index].company,
                name: snapshot.apiKeys[index].name,
                fallbackID: snapshot.apiKeys[index].id
            )
            syncRecordSecret(value: snapshot.apiKeys[index].key, account: account)
            snapshot.apiKeys[index].key = ""
        }

        // 搜索密钥同步
        for index in snapshot.searchKeys.indices {
            let account = secretAccount(
                namespace: "search",
                company: snapshot.searchKeys[index].company,
                name: snapshot.searchKeys[index].name,
                fallbackID: snapshot.searchKeys[index].id
            )
            syncRecordSecret(value: snapshot.searchKeys[index].key, account: account)
            snapshot.searchKeys[index].key = ""
        }

        // 工具密钥同步
        for index in snapshot.toolKeys.indices {
            let account = secretAccount(
                namespace: "tool",
                company: snapshot.toolKeys[index].company,
                name: snapshot.toolKeys[index].name,
                fallbackID: snapshot.toolKeys[index].id
            )
            syncRecordSecret(value: snapshot.toolKeys[index].key, account: account)
            snapshot.toolKeys[index].key = ""
        }
    }

    /// 迁移单个场景密钥
    private func migrateScenarioSecret(snapshot: inout AIScenarioConfig, scenario: AIScenario) -> Bool {
        guard let secret = snapshot.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else {
            return false
        }
        secretStore.write(secret, account: scenarioSecretAccount(scenario))
        snapshot.apiKey = nil
        return true
    }

    /// 同步单个场景密钥
    private func syncScenarioSecret(snapshot: inout AIScenarioConfig, scenario: AIScenario) {
        let account = scenarioSecretAccount(scenario)
        syncRecordSecret(value: snapshot.apiKey ?? "", account: account)
        snapshot.apiKey = nil
    }

    /// 同步单条密钥：空则删除，否则写入
    private func syncRecordSecret(value: String, account: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            secretStore.delete(account: account)
        } else {
            secretStore.write(normalized, account: account)
        }
    }

    // MARK: - 密钥存储路径
    /// 场景密钥存储标识
    private func scenarioSecretAccount(_ scenario: AIScenario) -> String {
        "scenario.\(scenario.rawValue).api_key"
    }

    /// 通用密钥存储标识（命名空间 + 厂商 + 名称）
    private func secretAccount(namespace: String, company: String, name: String, fallbackID: UUID) -> String {
        let normalizedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedCompany.isEmpty, normalizedName.isEmpty {
            return "\(namespace).__id__\(fallbackID.uuidString.lowercased())"
        }
        return "\(namespace).\(normalizedCompany).\(normalizedName)"
    }
}
