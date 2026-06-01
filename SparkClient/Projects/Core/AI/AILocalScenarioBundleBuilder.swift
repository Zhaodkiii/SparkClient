import Foundation

/// 由本地目录 `AllModels` + `APIKeys` 生成各业务场景的 `AIScenarioRemoteBundlesCollection`。
enum AILocalScenarioBundleBuilder {
    /// - Parameters:
    ///   - allModels: 用户模型目录（已启用条目参与组合）。
    ///   - apiKeys: 厂商密钥（按稳定 `providerID` 匹配）。
    ///   - scenarioBindings: 场景级模型绑定；不存在时该场景返回空列表。
    static func buildCollection(
        allModels: [AllModels],
        apiKeys: [APIKeys],
        scenarioBindings: [AIScenarioModelBinding]
    ) -> AIScenarioRemoteBundlesCollection {
        AIScenarioRemoteBundlesCollection(
            chat: buildBundle(for: .chat, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            embedding: buildBundle(for: .embedding, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            voice: buildBundle(for: .voice, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicalStructuredExtraction: buildBundle(for: .medicalStructuredExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicalDocumentTypeRecognition: buildBundle(for: .medicalDocumentTypeRecognition, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicalCaseExtraction: buildBundle(for: .medicalCaseExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            healthExamExtraction: buildBundle(for: .healthExamExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicalReportExtraction: buildBundle(for: .medicalReportExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            prescriptionExtraction: buildBundle(for: .prescriptionExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicationExtraction: buildBundle(for: .medicationExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            medicineBoxExtraction: buildBundle(for: .medicineBoxExtraction, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            optimizationText: buildBundle(for: .optimizationText, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            optimizationVisual: buildBundle(for: .optimizationVisual, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            contextFolding: buildBundle(for: .contextFolding, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            router: buildBundle(for: .router, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            modelConfig: buildBundle(for: .modelConfig, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings),
            reportInterpretation: buildBundle(for: .reportInterpretation, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings)
        )
    }

    private static func buildBundle(
        for scenario: AIScenario,
        allModels: [AllModels],
        apiKeys: [APIKeys],
        scenarioBindings: [AIScenarioModelBinding]
    ) -> AIScenarioRemoteBundle {
        let rows = localRows(for: scenario, allModels: allModels, apiKeys: apiKeys, scenarioBindings: scenarioBindings)
        guard rows.isEmpty == false else {
            return AIScenarioRemoteBundle(defaultModelName: "", models: [])
        }
        let defaultName: String = {
            rows.first(where: { $0.isDefault })?.name ?? rows.first?.name ?? ""
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
        apiKeys: [APIKeys],
        scenarioBindings: [AIScenarioModelBinding]
    ) -> [AIScenarioRemoteModelRow] {
        let modelsByID = Dictionary(uniqueKeysWithValues: allModels.map { ($0.id, $0) })
        let bindings = scenarioBindings
            .filter { $0.scenario == scenario.rawValue && $0.isActive }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.id.uuidString < $1.id.uuidString
            }

        return bindings.compactMap { binding in
            guard let model = modelsByID[binding.modelID], model.isEnabled else { return nil }
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
                systemProvision: blankToNil(binding.systemProvision) ?? blankToNil(model.systemProvision),
                icon: blankToNil(model.icon),
                briefDescription: blankToNil(binding.briefDescription) ?? blankToNil(model.briefDescription),
                source: model.source.rawValue,
                aiScenarios: [scenario.rawValue],
                aiToolScenarios: binding.aiToolScenarios.isEmpty ? model.aiToolScenarios : binding.aiToolScenarios,
                relatedTaskCodes: binding.relatedTaskCodes.isEmpty ? model.relatedTaskCodes : binding.relatedTaskCodes,
                isDefault: binding.isDefault,
                temperature: binding.temperature,
                maxTokens: binding.maxTokens,
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
