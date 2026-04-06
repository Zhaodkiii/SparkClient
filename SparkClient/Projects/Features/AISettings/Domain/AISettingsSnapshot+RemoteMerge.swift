import Foundation

extension AISettingsSnapshot {
    func merging(remotePatch: AIRemoteSettingsPatch) -> AISettingsSnapshot {
        var merged = self

        if let bundles = remotePatch.scenarioRemoteBundles {
            merged.scenarioRemoteBundles = bundles
            merged.pruneInvalidScenarioSelections()
            merged.materializeAllScenariosFromBundles()
        } else {
            if let chat = remotePatch.chat {
                merged.chat = mergeScenarioConfig(existing: merged.chat, incoming: chat)
            }
            if let optimizationText = remotePatch.optimizationText {
                merged.optimizationText = mergeScenarioConfig(existing: merged.optimizationText, incoming: optimizationText)
            }
            if let optimizationVisual = remotePatch.optimizationVisual {
                merged.optimizationVisual = mergeScenarioConfig(existing: merged.optimizationVisual, incoming: optimizationVisual)
            }
            if let contextFolding = remotePatch.contextFolding {
                merged.contextFolding = mergeScenarioConfig(existing: merged.contextFolding, incoming: contextFolding)
            }
            if let router = remotePatch.router {
                merged.router = mergeScenarioConfig(existing: merged.router, incoming: router)
            }
            if let modelConfig = remotePatch.modelConfig {
                merged.modelConfig = mergeScenarioConfig(existing: merged.modelConfig, incoming: modelConfig)
            }
            if let reportInterpretation = remotePatch.reportInterpretation {
                merged.reportInterpretation = mergeScenarioConfig(
                    existing: merged.reportInterpretation,
                    incoming: reportInterpretation
                )
            }
            merged.scenarioRemoteBundles = AIScenarioRemoteBundlesCollection.seededFromFlatSnapshots(
                chat: merged.chat,
                optimizationText: merged.optimizationText,
                optimizationVisual: merged.optimizationVisual,
                contextFolding: merged.contextFolding,
                router: merged.router,
                modelConfig: merged.modelConfig,
                reportInterpretation: merged.reportInterpretation
            )
        }

        if let apiKeys = remotePatch.apiKeys {
            merged.apiKeys = mergeAPIKeys(existing: merged.apiKeys, incoming: apiKeys)
        }
        if let searchKeys = remotePatch.searchKeys {
            merged.searchKeys = mergeSearchKeys(existing: merged.searchKeys, incoming: searchKeys)
        }
        if let toolKeys = remotePatch.toolKeys {
            merged.toolKeys = mergeToolKeys(existing: merged.toolKeys, incoming: toolKeys)
        }
        if let models = remotePatch.allModels {
            merged.allModels = mergeModels(existing: merged.allModels, incoming: models)
        }
        if let userInfoPatch = remotePatch.userInfo {
            merged.userInfo = mergeUserInfo(existing: merged.userInfo, patch: userInfoPatch)
        }
        if let trial = remotePatch.trial {
            merged.trial = trial
        }
        if let trialModelPolicy = remotePatch.trialModelPolicy {
            merged.trialModelPolicy = trialModelPolicy
            merged.pruneTrialChatPickerDisabledNames()
        }

        return merged
    }
}

private func mergeScenarioConfig(existing: AIScenarioConfig, incoming: AIScenarioConfig) -> AIScenarioConfig {
    var merged = existing
    if incoming.endpoint.isEmpty == false {
        merged.endpoint = incoming.endpoint
    }
    if incoming.model.isEmpty == false {
        merged.model = incoming.model
    }
    if let apiKey = incoming.apiKey, apiKey.isEmpty == false {
        merged.apiKey = apiKey
    }
    if incoming.maxTokens > 0 {
        merged.maxTokens = incoming.maxTokens
    }
    merged.temperature = incoming.temperature
    return merged
}

private func mergeAPIKeys(existing: [APIKeys], incoming: [APIKeys]) -> [APIKeys] {
    mergeRecordCollection(
        existing: existing,
        incoming: incoming,
        key: { record in
            dedupKey(company: record.company, name: record.name, fallbackID: record.id)
        }
    ) { old, new in
        if old.source == .custom, new.source == .system {
            var preserved = old
            preserved.requestURL = new.requestURL
            preserved.help = new.help
            preserved.isHidden = new.isHidden
            return preserved
        }
        return new
    }
}

private func mergeSearchKeys(existing: [SearchKeys], incoming: [SearchKeys]) -> [SearchKeys] {
    mergeRecordCollection(
        existing: existing,
        incoming: incoming,
        key: { record in
            dedupKey(company: record.company, name: record.name, fallbackID: record.id)
        }
    ) { old, new in
        if old.source == .custom, new.source == .system {
            return old
        }
        return new
    }
}

private func mergeToolKeys(existing: [ToolKeys], incoming: [ToolKeys]) -> [ToolKeys] {
    mergeRecordCollection(
        existing: existing,
        incoming: incoming,
        key: { record in
            dedupKey(company: record.company, name: record.name, fallbackID: record.id)
        }
    ) { old, new in
        if old.source == .custom, new.source == .system {
            return old
        }
        return new
    }
}

private func mergeModels(existing: [AllModels], incoming: [AllModels]) -> [AllModels] {
    mergeRecordCollection(
        existing: existing,
        incoming: incoming,
        key: { model in
            dedupKey(company: model.company, name: model.name, fallbackID: model.id)
        }
    ) { old, new in
        if old.source == .custom, new.source == .system {
            var preserved = old
            preserved.position = new.position
            preserved.priceTier = new.priceTier
            return preserved
        }
        return new
    }
}

private func mergeUserInfo(existing: UserInfo, patch: AIRemoteUserInfoPatch) -> UserInfo {
    var merged = existing

    if let chooseEmbeddingModel = patch.chooseEmbeddingModel, chooseEmbeddingModel.isEmpty == false {
        merged.chooseEmbeddingModel = chooseEmbeddingModel
    }
    if let optimizationTextModel = patch.optimizationTextModel, optimizationTextModel.isEmpty == false {
        merged.optimizationTextModel = optimizationTextModel
    }
    if let optimizationVisualModel = patch.optimizationVisualModel, optimizationVisualModel.isEmpty == false {
        merged.optimizationVisualModel = optimizationVisualModel
    }
    if let contextFoldingModel = patch.contextFoldingModel, contextFoldingModel.isEmpty == false {
        merged.contextFoldingModel = contextFoldingModel
    }
    if let routerModel = patch.routerModel, routerModel.isEmpty == false {
        merged.routerModel = routerModel
    }
    if let dataExtractionModel = patch.dataExtractionModel, dataExtractionModel.isEmpty == false {
        merged.dataExtractionModel = dataExtractionModel
    }
    if let reportInterpretationModel = patch.reportInterpretationModel, reportInterpretationModel.isEmpty == false {
        merged.reportInterpretationModel = reportInterpretationModel
    }
    if let textToSpeechModel = patch.textToSpeechModel, textToSpeechModel.isEmpty == false {
        merged.textToSpeechModel = textToSpeechModel
    }
    if let useContextFolding = patch.useContextFolding {
        merged.useContextFolding = useContextFolding
    }
    if let maxToolSets = patch.maxToolSets, maxToolSets > 0 {
        merged.maxToolSets = maxToolSets
    }

    if let useKnowledge = patch.useKnowledge {
        merged.useKnowledge = useKnowledge
    }
    if let knowledgeCount = patch.knowledgeCount, knowledgeCount > 0 {
        merged.knowledgeCount = knowledgeCount
    }
    if let knowledgeSimilarity = patch.knowledgeSimilarity, knowledgeSimilarity > 0 {
        merged.knowledgeSimilarity = knowledgeSimilarity
    }

    if let useSearch = patch.useSearch {
        merged.useSearch = useSearch
    }
    if let bilingualSearch = patch.bilingualSearch {
        merged.bilingualSearch = bilingualSearch
    }
    if let searchCount = patch.searchCount, searchCount > 0 {
        merged.searchCount = searchCount
    }

    if let useMap = patch.useMap {
        merged.useMap = useMap
    }
    if let useCalendar = patch.useCalendar {
        merged.useCalendar = useCalendar
    }
    if let useWeather = patch.useWeather {
        merged.useWeather = useWeather
    }
    if let useCanvas = patch.useCanvas {
        merged.useCanvas = useCanvas
    }
    if let useCode = patch.useCode {
        merged.useCode = useCode
    }

    return merged
}

private func mergeRecordCollection<T>(
    existing: [T],
    incoming: [T],
    key: (T) -> String,
    mergePair: (T, T) -> T
) -> [T] {
    let incomingKeys = Set(incoming.map(key))
    var map: [String: T] = [:]

    for item in existing {
        let itemKey = key(item)
        if incomingKeys.contains(itemKey) || isCustomRecord(item: item) {
            map[itemKey] = item
        }
    }

    for item in incoming {
        let itemKey = key(item)
        if let old = map[itemKey] {
            map[itemKey] = mergePair(old, item)
        } else {
            map[itemKey] = item
        }
    }

    return map.values.sorted { key($0) < key($1) }
}

private func isCustomRecord<T>(item: T) -> Bool {
    switch item {
    case let value as APIKeys:
        return value.source == .custom
    case let value as SearchKeys:
        return value.source == .custom
    case let value as ToolKeys:
        return value.source == .custom
    case let value as AllModels:
        return value.source == .custom
    default:
        return false
    }
}

private func dedupKey(company: String, name: String, fallbackID: UUID) -> String {
    let normalizedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let merged = "\(normalizedCompany)|\(normalizedName)"
    if merged.replacingOccurrences(of: "|", with: "").isEmpty {
        return "__id__\(fallbackID.uuidString.lowercased())"
    }
    return merged
}
