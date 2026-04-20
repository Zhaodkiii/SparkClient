import Foundation

enum AISettingsSeedLoader {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func loadAPIKeys(bundle: Bundle = .main) -> [APIKeys]? {
        guard let data = data(named: "APIKeys", bundle: bundle) else {
            return nil
        }
        do {
            let rows = try decoder.decode([APIKeySeedRow].self, from: data)
            return rows.map(\.model)
        } catch {
            #if DEBUG
            print("AISettingsSeedLoader.loadAPIKeys decode failed: \(error)")
            #endif
            return nil
        }
    }

    static func loadAllModels(bundle: Bundle = .main) -> [AllModels]? {
        guard
            let data = data(named: "AllModels", bundle: bundle),
            let rows = try? decoder.decode([AllModelSeedRow].self, from: data)
        else {
            return nil
        }
        return rows.enumerated().map { index, row in
            row.model(position: index)
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
}

private struct APIKeySeedRow: Decodable {
    let name: String
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
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios,
            source: AIRecordSource(rawValue: (source ?? "system").lowercased()) ?? .system
        )
    }
}
