import Foundation

/// 由本地目录 `AllModels` + `APIKeys` 生成各业务场景的 `AIScenarioRemoteBundlesCollection`。
enum AILocalScenarioBundleBuilder {
    /// - Parameters:
    ///   - allModels: 用户模型目录（已启用条目参与组合）。
    ///   - apiKeys: 厂商密钥（按稳定 `providerID` 匹配）。
    ///   - scenarioDefaults: 场景级用户默认模型名（scenario rawValue -> model name）；不存在或无效时回退到本场景列表首条。
    static func buildCollection(
        allModels: [AllModels],
        apiKeys: [APIKeys],
        scenarioDefaults: [String: String]
    ) -> AIScenarioRemoteBundlesCollection {
        AIScenarioRemoteBundlesCollection(
            chat: buildBundle(for: .chat, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            embedding: buildBundle(for: .embedding, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            voice: buildBundle(for: .voice, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            medicalStructuredExtraction: buildBundle(for: .medicalStructuredExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            medicalDocumentTypeRecognition: buildBundle(for: .medicalDocumentTypeRecognition, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            medicalCaseExtraction: buildBundle(for: .medicalCaseExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            healthExamExtraction: buildBundle(for: .healthExamExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            medicalReportExtraction: buildBundle(for: .medicalReportExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            prescriptionExtraction: buildBundle(for: .prescriptionExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            medicationExtraction: buildBundle(for: .medicationExtraction, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            optimizationText: buildBundle(for: .optimizationText, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            optimizationVisual: buildBundle(for: .optimizationVisual, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            contextFolding: buildBundle(for: .contextFolding, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            router: buildBundle(for: .router, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            modelConfig: buildBundle(for: .modelConfig, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults),
            reportInterpretation: buildBundle(for: .reportInterpretation, allModels: allModels, apiKeys: apiKeys, scenarioDefaults: scenarioDefaults)
        )
    }

    private static func buildBundle(
        for scenario: AIScenario,
        allModels: [AllModels],
        apiKeys: [APIKeys],
        scenarioDefaults: [String: String]
    ) -> AIScenarioRemoteBundle {
        let rows = localRows(for: scenario, allModels: allModels, apiKeys: apiKeys)
        guard rows.isEmpty == false else {
            return AIScenarioRemoteBundle(defaultModelName: "", models: [])
        }
        let preferredName = scenarioDefaults[scenario.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName: String = {
            if let preferredName, preferredName.isEmpty == false,
               rows.contains(where: { $0.name == preferredName })
            {
                return preferredName
            }
            return rows.first?.name ?? ""
        }()
        let models = rows.map { row in
            var m = row
            m.isDefault = m.name == defaultName
            return m
        }
        return AIScenarioRemoteBundle(defaultModelName: defaultName, models: models)
    }

    private static func localRows(
        for scenario: AIScenario,
        allModels: [AllModels],
        apiKeys: [APIKeys]
    ) -> [AIScenarioRemoteModelRow] {
        let enabledModels = allModels
            .filter { $0.isEnabled }
            .filter { model in
                let scenarios = Set(model.aiScenarios)
                if scenarios.contains(scenario.rawValue) {
                    return true
                }
                if scenarios.isEmpty {
                    switch scenario {
                    case .chat:
                        return model.supportsTextGen
                    case .embedding:
                        let lowerName = model.name.lowercased()
                        return lowerName.contains("embedding") || lowerName.hasPrefix("text-embedding") || lowerName.contains("bge")
                    case .voice:
                        return model.supportsVoiceGen
                    default:
                        return false
                    }
                }
                return false
            }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position {
                    return lhs.position < rhs.position
                }
                return lhs.displayName < rhs.displayName
            }

        let fallbackModels: [AllModels]
        switch scenario {
        case .chat:
            fallbackModels = enabledModels
        case .embedding:
            fallbackModels = enabledModels.isEmpty
                ? allModels.filter {
                    $0.isEnabled &&
                    ($0.name.lowercased().contains("embedding") || $0.name.lowercased().hasPrefix("text-embedding") || $0.name.lowercased().contains("bge"))
                }
                : enabledModels
        case .voice:
            fallbackModels = enabledModels.isEmpty
                ? allModels.filter { $0.isEnabled && $0.supportsVoiceGen }
                : enabledModels
        default:
            fallbackModels = enabledModels.isEmpty
                ? allModels.filter { $0.isEnabled && $0.supportsTextGen }
                : enabledModels
        }

        let modelsToUse = fallbackModels.isEmpty ? allModels.filter { $0.isEnabled && $0.supportsTextGen } : fallbackModels

        return modelsToUse.compactMap { model in
            let provider = apiKeys.first {
                $0.providerID == model.providerID
                    && $0.isEnabled
            }
            let endpoint = provider?.requestURL ?? (model.isLocalModel ? "local://chat/completions" : "")
            guard endpoint.isEmpty == false else { return nil }
            return AIScenarioRemoteModelRow(
                name: model.name,
                displayName: model.displayName,
                identity: model.identity.rawValue,
                providerID: model.providerID,
                company: model.company,
                endpoint: endpoint,
                apiKey: blankToNil(provider?.key),
                supportsSearch: model.supportsSearch,
                supportsMultimodal: model.supportsMultimodal,
                supportsReasoning: model.supportsReasoning,
                supportsToolUse: model.supportsToolUse,
                supportsVoiceGen: model.supportsVoiceGen,
                supportsImageGen: model.supportsImageGen,
                supportsText: model.supportsTextGen,
                supportsDeepReasoning: model.supportsReasoning,
                reasoningControllable: model.supportReasoningChange,
                priceTier: model.price,
                systemProvision: blankToNil(model.systemProvision),
                icon: blankToNil(model.icon),
                briefDescription: blankToNil(model.briefDescription),
                source: model.source.rawValue,
                aiScenarios: model.aiScenarios,
                aiToolScenarios: model.aiToolScenarios,
                relatedTaskCodes: model.relatedTaskCodes,
                isDefault: false,
                temperature: scenario == .chat ? 0.6 : 0.2,
                maxTokens: 4096,
                baseModelName: model.baseModelName,
                localFilename: model.localFilename
            )
        }
    }

    private static func blankToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
