import Foundation

enum AISettingsMutationError: LocalizedError {
    case providerNotFound
    case providerKeyRequired(String)
    case modelNotFound
    case systemModelCannotBeDeleted

    var errorDescription: String? {
        switch self {
        case .providerNotFound:
            return L10n.text("common.operation_failed")
        case .providerKeyRequired(let displayName):
            return String(format: L10n.text("ai_settings.providers.error.key_required_with_name"), displayName)
        case .modelNotFound:
            return L10n.text("common.operation_failed")
        case .systemModelCannotBeDeleted:
            return L10n.text("ai_settings.models.alert.cannot_delete_system")
        }
    }
}

struct ProviderSettingsCoordinator: Sendable {
    func appendProvider(_ provider: APIKeys, in snapshot: inout AISettingsSnapshot) {
        snapshot.apiKeys.append(provider)
    }

    @discardableResult
    func setProviderEnabled(recordID: UUID, enabled: Bool, in snapshot: inout AISettingsSnapshot) throws -> APIKeys {
        guard let index = snapshot.apiKeys.firstIndex(where: { $0.id == recordID }) else {
            throw AISettingsMutationError.providerNotFound
        }
        let provider = snapshot.apiKeys[index]
        if enabled && provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AISettingsMutationError.providerKeyRequired(provider.localizedDisplayName)
        }

        snapshot.apiKeys[index].isHidden = !enabled
        snapshot.apiKeys[index].timestamp = Date()
        setModelsHidden(providerID: provider.providerID, hidden: !enabled, in: &snapshot)
        return snapshot.apiKeys[index]
    }

    @discardableResult
    func saveProviderFromEditor(_ provider: APIKeys, in snapshot: inout AISettingsSnapshot) -> APIKeys {
        var updated = provider
        updated.privacyPolicyAcceptedAt = updated.privacyPolicyAccepted ? Date() : nil
        updated.timestamp = Date()
        updated.isHidden = updated.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if let index = snapshot.apiKeys.firstIndex(where: { $0.id == updated.id }) {
            snapshot.apiKeys[index] = updated
        } else {
            snapshot.apiKeys.append(updated)
        }
        setModelsHidden(providerID: updated.providerID, hidden: updated.isHidden, in: &snapshot)
        return updated
    }

    private func setModelsHidden(providerID: String, hidden: Bool, in snapshot: inout AISettingsSnapshot) {
        for index in snapshot.allModels.indices where snapshot.allModels[index].providerID == providerID {
            snapshot.allModels[index].isHidden = hidden
        }
    }
}

struct ModelCatalogCoordinator: Sendable {
    @discardableResult
    func initializeModelVisibility(in snapshot: inout AISettingsSnapshot) -> Bool {
        var didChange = false
        for index in snapshot.allModels.indices {
            let model = snapshot.allModels[index]
            guard model.isHidden == false, hasValidAPIKey(for: model, in: snapshot) == false else { continue }
            snapshot.allModels[index].isHidden = true
            didChange = true
        }
        return didChange
    }

    func hasValidAPIKey(for model: AllModels, in snapshot: AISettingsSnapshot) -> Bool {
        if AIProviderAdapterRegistry.adapter(for: model.providerID).isLocal {
            return true
        }
        return snapshot.apiKeys.contains { key in
            key.providerID == model.providerID &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    func deleteModel(id: UUID, in snapshot: inout AISettingsSnapshot) throws {
        guard let model = snapshot.allModels.first(where: { $0.id == id }) else {
            throw AISettingsMutationError.modelNotFound
        }
        guard model.source != .system else {
            throw AISettingsMutationError.systemModelCannotBeDeleted
        }
        snapshot.allModels.removeAll { $0.id == id }
    }

    @discardableResult
    func createLocalAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        in snapshot: inout AISettingsSnapshot
    ) -> AllModels? {
        guard let baseModel = snapshot.allModels.first(where: { $0.name == baseModelName }) else { return nil }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { return nil }

        let agentPositions = snapshot.allModels.filter { $0.identity == .agent }.map(\.position)
        let position = (agentPositions.max() ?? 999) + 1
        // Use a unique name so the agent never collides with its base model in scenario bundles
        let uniqueName = "agent-\(UUID().uuidString)"
        let agent = AllModels(
            name: uniqueName,
            displayName: trimmedName,
            identity: .agent,
            position: position,
            providerID: baseModel.providerID,
            company: baseModel.company,
            isHidden: false,
            supportsSearch: baseModel.supportsSearch,
            supportsMultimodal: baseModel.supportsMultimodal,
            supportsReasoning: baseModel.supportsReasoning,
            supportsToolUse: baseModel.supportsToolUse,
            supportsVoiceGen: baseModel.supportsVoiceGen,
            supportsImageGen: baseModel.supportsImageGen,
            iconSymbol: iconSymbol,
            baseModelName: baseModel.name,
            localFilename: nil,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .custom,
            timestamp: Date(),
            priceTier: baseModel.priceTier,
            supportsText: baseModel.supportsText,
            reasoningControllable: baseModel.reasoningControllable,
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes
        )
        snapshot.allModels.append(agent)
        return agent
    }

    func updateLocalAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        in snapshot: inout AISettingsSnapshot
    ) {
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == id }) else { return }
        var model = snapshot.allModels[index]
        guard model.identity == .agent, model.source != .system else { return }
        model.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.iconSymbol = iconSymbol
        model.baseModelName = baseModelName
        model.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        model.selectedToolNames = Set(aiToolScenarios)
        model.relatedTaskCodes = relatedTaskCodes.sorted()
        if let base = snapshot.allModels.first(where: { $0.name == baseModelName && $0.identity == .model }) {
            model.providerID = base.providerID
            model.company = base.company
            model.supportsSearch = base.supportsSearch
            model.supportsMultimodal = base.supportsMultimodal
            model.supportsReasoning = base.supportsReasoning
            model.supportsToolUse = base.supportsToolUse
            model.supportsVoiceGen = base.supportsVoiceGen
            model.supportsImageGen = base.supportsImageGen
            model.supportsText = base.supportsText
            model.reasoningControllable = base.reasoningControllable
            model.priceTier = base.priceTier
        }
        snapshot.allModels[index] = model
    }
}
