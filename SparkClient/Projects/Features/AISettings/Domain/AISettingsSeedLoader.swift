import Foundation

enum AISettingsSeedLoader {
    static func loadAPIKeys(bundle: Bundle = .main) -> [APIKeys]? {
        guard let data = data(named: "APIKeys", bundle: bundle) else {
            return nil
        }
        do {
            let rows = try JSONDecoder.default.decode([APIKeySeedRow].self, from: data)
            return rows.map(\.model)
        } catch {
            logDecodeFailure("loadAPIKeys", error: error)
            return nil
        }
    }

    static func loadAllModels(bundle: Bundle = .main) -> [AllModels]? {
        guard let data = data(named: "AllModels", bundle: bundle) else {
            return nil
        }
        do {
            let rows = try JSONDecoder.default.decode([AllModelSeedRow].self, from: data)
            return rows.enumerated().map { index, row in
                row.model(position: index)
            }
        } catch {
            logDecodeFailure("loadAllModels", error: error)
            return nil
        }
    }

    static func loadScenarioBindings(bundle: Bundle = .main) -> [AIScenarioModelBinding]? {
        guard let models = loadAllModels(bundle: bundle) else { return nil }
        return loadScenarioBindings(for: models, bundle: bundle)
    }

    static func loadScenarioBindings(for models: [AllModels], bundle: Bundle = .main) -> [AIScenarioModelBinding]? {
        guard let data = data(named: "AllModels", bundle: bundle) else {
            return nil
        }
        let rows: [AllModelSeedRow]
        do {
            rows = try JSONDecoder.default.decode([AllModelSeedRow].self, from: data)
        } catch {
            logDecodeFailure("loadScenarioBindings", error: error)
            return nil
        }
        var positions: [String: Int] = [:]
        var hasDefault: Set<String> = []
        return zip(rows, models).flatMap { row, model in
            row.aiScenarios.compactMap { scenarioRaw in
                guard AIScenario(rawValue: scenarioRaw) != nil else { return nil }
                let position = positions[scenarioRaw, default: 0]
                positions[scenarioRaw] = position + 1
                let isDefault = hasDefault.contains(scenarioRaw) == false
                if isDefault {
                    hasDefault.insert(scenarioRaw)
                }
                return AIScenarioModelBinding(
                    scenario: scenarioRaw,
                    identity: model.identity,
                    modelID: model.id,
                    temperature: AIScenarioModelBinding.defaultTemperature,
                    maxTokens: AIScenarioModelBinding.defaultMaxTokens,
                    position: position,
                    isDefault: isDefault,
                    systemProvision: row.systemProvision,
                    briefDescription: row.briefDescription,
                    aiToolScenarios: row.aiToolScenarios
                )
            }
        }
    }

    private static func data(named resource: String, bundle: Bundle) -> Data? {
        if let url = bundle.url(forResource: resource, withExtension: "json", subdirectory: "AISettings") {
            return try? Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: resource, withExtension: "json") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    private static func logDecodeFailure(_ scope: String, error: Error) {
        #if DEBUG
        print("AISettingsSeedLoader.\(scope) decode failed: \(error)")
        #endif
    }
}

private struct APIKeySeedRow: Decodable {
    let name: String
    let providerID: String?
    let company: String
    let key: String
    let requestURL: String
    let help: String
    let from: String
    let privacyPolicyURL: String
    let isEnabled: Bool?
    let source: String?

    var model: APIKeys {
        APIKeys(
            providerID: providerID,
            name: name,
            company: company,
            key: key,
            requestURL: requestURL,
            help: help,
            from: from,
            privacyPolicyURL: privacyPolicyURL,
            isEnabled: isEnabled ?? true,
            source: AIRecordSource(rawValue: (source ?? "system").lowercased()) ?? .system
        )
    }
}

private struct AllModelSeedRow: Decodable {
    let name: String
    let displayName: String
    let identity: AIModelIdentity
    let providerID: String?
    let company: String
    let price: Int
    let isEnabled: Bool
    let supportsSearch: Bool
    let supportsTextGen: Bool
    let supportsMultimodal: Bool
    let supportsReasoning: Bool
    let supportReasoningChange: Bool
    let supportsImageGen: Bool
    let supportsVoiceGen: Bool
    let supportsToolUse: Bool
    let systemProvision: String
    let icon: String
    let briefDescription: String
    let characterDesign: String
    let aiScenarios: [String]
    let aiToolScenarios: [String]
    let source: String?

    func model(position: Int) -> AllModels {
        AllModels(
            name: name,
            displayName: displayName,
            identity: identity,
            position: position,
            providerID: providerID,
            company: company,
            price: price,
            isEnabled: isEnabled,
            supportsSearch: supportsSearch,
            supportsTextGen: supportsTextGen,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: supportReasoningChange,
            supportsImageGen: supportsImageGen,
            supportsVoiceGen: supportsVoiceGen,
            supportsToolUse: supportsToolUse,
            systemProvision: systemProvision,
            icon: icon,
            briefDescription: briefDescription,
            characterDesign: characterDesign,
            aiToolScenarios: aiToolScenarios,
            source: AIRecordSource(rawValue: (source ?? "system").lowercased()) ?? .system
        )
    }
}
