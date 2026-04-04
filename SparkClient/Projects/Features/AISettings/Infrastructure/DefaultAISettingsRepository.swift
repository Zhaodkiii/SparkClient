import Foundation

final class DefaultAISettingsRepository: AISettingsRepository, @unchecked Sendable {
    private enum Keys {
        static let snapshot = "spark.ai.settings.snapshot.v1"
    }

    private let userDefaults: UserDefaults
    private let secretStore: any AISettingsSecretStore
    private let encoder = JSONEncoder()
    private let logger: Logger

    init(
        userDefaults: UserDefaults = .standard,
        secretStore: any AISettingsSecretStore = KeychainAISettingsSecretStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
        self.logger = logger
    }

    func loadSnapshot() async -> AISettingsSnapshot {
        var loaded = loadPersistedSnapshot() ?? .default
        var migrated = false

        if migrateLegacySecretsToStore(snapshot: &loaded) {
            migrated = true
        }
        loaded = preloadIfNeeded(snapshot: loaded)
        hydrateSecrets(snapshot: &loaded)

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

    func save(snapshot: AISettingsSnapshot) async throws {
        try persist(snapshot: snapshot)
        logger.info("AI 设置快照已保存", category: "ai_settings")
    }

    private func persist(snapshot: AISettingsSnapshot) throws {
        var sanitized = snapshot
        syncSecretsToStoreAndSanitize(snapshot: &sanitized)
        let data = try encoder.encode(sanitized)
        userDefaults.set(data, forKey: Keys.snapshot)
    }

    private func loadPersistedSnapshot() -> AISettingsSnapshot? {
        guard let data = userDefaults.data(forKey: Keys.snapshot) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(AISettingsSnapshot.self, from: data)
    }

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

    // MARK: - Preload / Dedup

    private func preloadModelDataIfNeeded(snapshot: inout AISettingsSnapshot) {
        let predefinedModels = AISettingsSeedCatalog.getModelList()
        let predefinedModelKeys = Set(predefinedModels.map { dedupKey(name: $0.name, fallbackID: $0.id) })

        var modelMap: [String: AllModels] = [:]
        for model in snapshot.allModels {
            let key = dedupKey(name: model.name, fallbackID: model.id)
            if model.source == .system, predefinedModelKeys.contains(key) == false {
                continue
            }
            if let existing = modelMap[key] {
                modelMap[key] = mergeModel(existing: existing, incoming: model)
            } else {
                modelMap[key] = model
            }
        }
        for preset in predefinedModels {
            let key = dedupKey(name: preset.name, fallbackID: preset.id)
            if let existing = modelMap[key] {
                modelMap[key] = mergeModel(existing: existing, incoming: preset)
            } else {
                modelMap[key] = preset
            }
        }
        snapshot.allModels = modelMap.values.sorted { lhs, rhs in
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            return dedupKey(name: lhs.name, fallbackID: lhs.id) < dedupKey(name: rhs.name, fallbackID: rhs.id)
        }
    }

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
        if incoming.source == .custom {
            return incoming
        }
        return existing
    }

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
            if old.source == .custom, new.source == .system {
                return old
            }
            if new.source == .custom {
                return new
            }
            if old.key.isEmpty, new.key.isEmpty == false {
                return new
            }
            return old
        }
    }

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

    private func preloadPromptIfNeeded(snapshot: inout AISettingsSnapshot) {
        let defaultPrompts = AISettingsSeedCatalog.getPromptList()
        let defaultTitles = Set(defaultPrompts.map(\.title))
        var merged = snapshot.promptRepo
        for preset in defaultPrompts where merged.contains(where: { $0.title == preset.title }) == false {
            merged.append(preset)
        }
        snapshot.promptRepo = merged.filter { record in
            if record.isSystem {
                return defaultTitles.contains(record.title)
            }
            return true
        }
    }

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

    private func dedupKey(name: String, fallbackID: UUID) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "__id__\(fallbackID.uuidString.lowercased())"
        }
        return normalized
    }

    // MARK: - Secret Sync

    private func migrateLegacySecretsToStore(snapshot: inout AISettingsSnapshot) -> Bool {
        var changed = false

        changed = migrateScenarioSecret(snapshot: &snapshot.chat, scenario: .chat) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.optimizationText, scenario: .optimizationText) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.optimizationVisual, scenario: .optimizationVisual) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.contextFolding, scenario: .contextFolding) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.router, scenario: .router) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.modelConfig, scenario: .modelConfig) || changed
        changed = migrateScenarioSecret(snapshot: &snapshot.reportInterpretation, scenario: .reportInterpretation) || changed

        for index in snapshot.apiKeys.indices {
            let secret = snapshot.apiKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.isEmpty == false else { continue }
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

        for index in snapshot.searchKeys.indices {
            let secret = snapshot.searchKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.isEmpty == false else { continue }
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

        for index in snapshot.toolKeys.indices {
            let secret = snapshot.toolKeys[index].key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.isEmpty == false else { continue }
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

    private func hydrateSecrets(snapshot: inout AISettingsSnapshot) {
        snapshot.chat.apiKey = secretStore.read(account: scenarioSecretAccount(.chat))
        snapshot.optimizationText.apiKey = secretStore.read(account: scenarioSecretAccount(.optimizationText))
        snapshot.optimizationVisual.apiKey = secretStore.read(account: scenarioSecretAccount(.optimizationVisual))
        snapshot.contextFolding.apiKey = secretStore.read(account: scenarioSecretAccount(.contextFolding))
        snapshot.router.apiKey = secretStore.read(account: scenarioSecretAccount(.router))
        snapshot.modelConfig.apiKey = secretStore.read(account: scenarioSecretAccount(.modelConfig))
        snapshot.reportInterpretation.apiKey = secretStore.read(account: scenarioSecretAccount(.reportInterpretation))

        for index in snapshot.apiKeys.indices {
            let account = secretAccount(
                namespace: "api",
                company: snapshot.apiKeys[index].company,
                name: snapshot.apiKeys[index].name,
                fallbackID: snapshot.apiKeys[index].id
            )
            snapshot.apiKeys[index].key = secretStore.read(account: account) ?? ""
        }

        for index in snapshot.searchKeys.indices {
            let account = secretAccount(
                namespace: "search",
                company: snapshot.searchKeys[index].company,
                name: snapshot.searchKeys[index].name,
                fallbackID: snapshot.searchKeys[index].id
            )
            snapshot.searchKeys[index].key = secretStore.read(account: account) ?? ""
        }

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

    private func syncSecretsToStoreAndSanitize(snapshot: inout AISettingsSnapshot) {
        syncScenarioSecret(snapshot: &snapshot.chat, scenario: .chat)
        syncScenarioSecret(snapshot: &snapshot.optimizationText, scenario: .optimizationText)
        syncScenarioSecret(snapshot: &snapshot.optimizationVisual, scenario: .optimizationVisual)
        syncScenarioSecret(snapshot: &snapshot.contextFolding, scenario: .contextFolding)
        syncScenarioSecret(snapshot: &snapshot.router, scenario: .router)
        syncScenarioSecret(snapshot: &snapshot.modelConfig, scenario: .modelConfig)
        syncScenarioSecret(snapshot: &snapshot.reportInterpretation, scenario: .reportInterpretation)

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

    private func migrateScenarioSecret(snapshot: inout AIScenarioConfig, scenario: AIScenario) -> Bool {
        guard let secret = snapshot.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), secret.isEmpty == false else {
            return false
        }
        secretStore.write(secret, account: scenarioSecretAccount(scenario))
        snapshot.apiKey = nil
        return true
    }

    private func syncScenarioSecret(snapshot: inout AIScenarioConfig, scenario: AIScenario) {
        let account = scenarioSecretAccount(scenario)
        syncRecordSecret(value: snapshot.apiKey ?? "", account: account)
        snapshot.apiKey = nil
    }

    private func syncRecordSecret(value: String, account: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            secretStore.delete(account: account)
        } else {
            secretStore.write(normalized, account: account)
        }
    }

    private func scenarioSecretAccount(_ scenario: AIScenario) -> String {
        "scenario.\(scenario.rawValue).api_key"
    }

    private func secretAccount(namespace: String, company: String, name: String, fallbackID: UUID) -> String {
        let normalizedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedCompany.isEmpty, normalizedName.isEmpty {
            return "\(namespace).__id__\(fallbackID.uuidString.lowercased())"
        }
        return "\(namespace).\(normalizedCompany).\(normalizedName)"
    }
}
