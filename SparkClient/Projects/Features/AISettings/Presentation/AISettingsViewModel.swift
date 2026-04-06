import Combine
import Foundation

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var snapshot: AISettingsSnapshot = .default
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var saveSucceeded = false
    @Published private(set) var trialOperationInFlight = false

    private let loadUseCase: LoadAISettingsUseCase
    private let saveUseCase: SaveAISettingsUseCase
    private let aiConfigAPI: SparkAIConfigAPI?
    private let localModelService: LocalModelService
    private var lastPersistedSnapshot: AISettingsSnapshot = .default
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadUseCase: LoadAISettingsUseCase,
        saveUseCase: SaveAISettingsUseCase,
        localModelService: LocalModelService = LocalModelService(),
        aiConfigAPI: SparkAIConfigAPI? = nil
    ) {
        self.loadUseCase = loadUseCase
        self.saveUseCase = saveUseCase
        self.localModelService = localModelService
        self.aiConfigAPI = aiConfigAPI
        bindSnapshotChanges()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let loaded = await loadUseCase.execute()
        lastPersistedSnapshot = loaded
        snapshot = loaded
        hasUnsavedChanges = false
    }

    func save() async {
        guard hasUnsavedChanges else { return }
        isSaving = true
        errorMessage = nil
        saveSucceeded = false
        defer { isSaving = false }

        do {
            try await saveUseCase.execute(snapshot: snapshot)
            lastPersistedSnapshot = snapshot
            hasUnsavedChanges = false
            saveSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSaveFlag() {
        saveSucceeded = false
    }

    func refreshTrialStatus() async {
        guard let aiConfigAPI else { return }
        trialOperationInFlight = true
        defer { trialOperationInFlight = false }
        do {
            let state = try await aiConfigAPI.fetchTrialStatus()
            snapshot.trial = state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func submitTrialApplication(note: String = "") async -> Bool {
        guard let aiConfigAPI else { return false }
        trialOperationInFlight = true
        defer { trialOperationInFlight = false }
        do {
            let state = try await aiConfigAPI.applyTrial(note: note)
            snapshot.trial = state
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func testProviderConnection(requestURL: String, apiKey: String, model: String) async -> Bool {
        guard let aiConfigAPI else { return false }
        do {
            return try await aiConfigAPI.testProviderConnection(
                requestURL: requestURL,
                apiKey: apiKey,
                model: model
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func localModelCatalog() -> [LocalModelCatalogItem] {
        localModelService.builtInCatalog()
    }

    func installLocalModel(item: LocalModelCatalogItem) async throws {
        let installed = try await localModelService.downloadModel(item)
        upsertLocalBaseModel(installed)
    }

    func importLocalModel(from fileURL: URL, preferredDisplayName: String? = nil) async throws {
        let installed = try await localModelService.importModel(from: fileURL, preferredDisplayName: preferredDisplayName)
        upsertLocalBaseModel(installed)
    }

    /// 与 Health「添加在线模型」一致：写入唯一 `name` 后追加到目录。
    func appendOnlineModel(
        name: String,
        displayName: String,
        company: String,
        priceTier: Int,
        isHidden: Bool,
        supportsText: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        reasoningControllable: Bool,
        supportsToolUse: Bool,
        supportsImageGen: Bool
    ) {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = company.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseName.isEmpty == false, baseDisplay.isEmpty == false, co.isEmpty == false else { return }
        var uniqueName = baseName
        if snapshot.allModels.contains(where: { $0.name == uniqueName }) {
            uniqueName = baseName + "_" + UUID().uuidString.prefix(8).lowercased()
        }
        var uniqueDisplay = baseDisplay
        if snapshot.allModels.contains(where: { $0.displayName == uniqueDisplay && $0.company == co }) {
            uniqueDisplay = baseDisplay + " (\(UUID().uuidString.prefix(4)))"
        }
        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
        let tier = min(max(priceTier, 0), 3)
        let model = AllModels(
            name: uniqueName,
            displayName: uniqueDisplay,
            identity: .model,
            position: position,
            company: co,
            isHidden: isHidden,
            supportsSearch: true,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportsToolUse: supportsToolUse,
            supportsVoiceGen: false,
            supportsImageGen: supportsImageGen,
            source: .custom,
            timestamp: Date(),
            priceTier: tier,
            supportsText: supportsText,
            reasoningControllable: reasoningControllable
        )
        snapshot.allModels.append(model)
    }

    /// 替换目录中一条模型（触发 `snapshot` 更新）。
    func replaceModel(_ model: AllModels) {
        guard let idx = snapshot.allModels.firstIndex(where: { $0.id == model.id }) else { return }
        snapshot.allModels[idx] = model
    }

    /// 更新本地智能体（编辑 Sheet 保存）。
    func updateLocalAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String
    ) {
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == id }) else { return }
        var m = snapshot.allModels[index]
        guard m.isLocalAgent else { return }
        m.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        m.iconSymbol = iconSymbol
        m.baseModelName = baseModelName
        m.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let base = snapshot.allModels.first(where: { $0.name == baseModelName && $0.isLocalModel }) {
            m.supportsSearch = base.supportsSearch
            m.supportsMultimodal = base.supportsMultimodal
            m.supportsReasoning = base.supportsReasoning
            m.supportsToolUse = base.supportsToolUse
            m.supportsVoiceGen = base.supportsVoiceGen
            m.supportsImageGen = base.supportsImageGen
            m.supportsText = base.supportsText
            m.reasoningControllable = base.reasoningControllable
            m.priceTier = base.priceTier
        }
        snapshot.allModels[index] = m
    }

    func removeLocalModel(_ model: AllModels) async throws {
        guard let filename = model.localFilename, filename.isEmpty == false else {
            snapshot.allModels.removeAll { $0.id == model.id }
            return
        }
        try await localModelService.deleteModel(fileName: filename)
        snapshot.allModels.removeAll { candidate in
            candidate.id == model.id || candidate.baseModelName == model.name
        }
        if snapshot.chat.model == model.name {
            snapshot.scenarioSelectedModel[AIScenario.chat.rawValue] = nil
            snapshot.chat.model = AISettingsSnapshot.default.chat.model
            snapshot.chat.endpoint = AISettingsSnapshot.default.chat.endpoint
            snapshot.chat.apiKey = nil
            snapshot.materializeAllScenariosFromBundles()
        }
    }

    /// 试用对话模型：是否在输入栏候选中隐藏（持久化 `trialChatPickerDisabledModelNames`）。
    func setTrialChatPickerDisabled(modelName: String, disabled: Bool) {
        var set = Set(snapshot.trialChatPickerDisabledModelNames)
        if disabled {
            set.insert(modelName)
        } else {
            set.remove(modelName)
        }
        snapshot.trialChatPickerDisabledModelNames = Array(set).sorted()
    }

    func setChatModel(_ model: AllModels) {
        snapshot.scenarioSelectedModel[AIScenario.chat.rawValue] = model.name
        if model.company.uppercased() == LocalModelService.localCompany {
            snapshot.chat.endpoint = "local://chat/completions"
            snapshot.chat.apiKey = nil
            snapshot.chat.model = model.name
            return
        }

        if let row = snapshot.scenarioRemoteBundles?.chat.models.first(where: { $0.model == model.name }) {
            snapshot.chat = row.asScenarioConfig()
            return
        }

        snapshot.chat.model = model.name
        if let provider = snapshot.apiKeys.first(where: { $0.company.uppercased() == model.company.uppercased() }) {
            snapshot.chat.endpoint = provider.requestURL
            snapshot.chat.apiKey = provider.key.isEmpty ? nil : provider.key
        }
    }

    func createLocalAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String
    ) {
        guard let baseModel = snapshot.allModels.first(where: { $0.name == baseModelName }) else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { return }

        let agentPositions = snapshot.allModels.filter { $0.identity == .agent }.map(\.position)
        let position = (agentPositions.max() ?? 999) + 1
        let agent = AllModels(
            name: "local-agent-\(UUID().uuidString.lowercased())",
            displayName: trimmedName,
            identity: .agent,
            position: position,
            company: LocalModelService.localCompany,
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
            reasoningControllable: baseModel.reasoningControllable
        )
        snapshot.allModels.append(agent)
    }

    private func upsertLocalBaseModel(_ installed: LocalModelInstalled) {
        let localCompany = LocalModelService.localCompany
        if let index = snapshot.allModels.firstIndex(where: { $0.localFilename == installed.fileName && $0.identity == .model }) {
            snapshot.allModels[index].displayName = installed.displayName
            snapshot.allModels[index].name = installed.modelName
            snapshot.allModels[index].company = localCompany
            snapshot.allModels[index].isHidden = false
            snapshot.allModels[index].source = .custom
            snapshot.allModels[index].timestamp = Date()
            return
        }

        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
        snapshot.allModels.append(
            AllModels(
                name: installed.modelName,
                displayName: installed.displayName,
                identity: .model,
                position: position,
                company: localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "cpu",
                baseModelName: nil,
                localFilename: installed.fileName,
                systemPrompt: nil,
                source: .custom,
                timestamp: Date()
            )
        )
    }

    private func bindSnapshotChanges() {
        $snapshot
            .dropFirst()
            .sink { [weak self] latest in
                guard let self else { return }
                self.hasUnsavedChanges = latest != self.lastPersistedSnapshot
            }
            .store(in: &cancellables)
    }
}
