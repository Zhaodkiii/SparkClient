import Combine
import Foundation

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var snapshot: AISettingsSnapshot = .default
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var trialOperationInFlight = false

    private let loadUseCase: LoadAISettingsUseCase
    private let saveUseCase: SaveAISettingsUseCase
    /// 与 `UserSession.accountID` 一致时，不依赖会话快照解析顺序即可命中该账号的 Core Data 目录。
    private let ownerAccountIDForLoad: Int64?
    private let aiConfigAPI: SparkAIConfigAPI?
    private let aiConfigCenter: AIConfigCenter?
    private let localModelService: LocalModelService
    private let providerModelCatalogService: ProviderModelCatalogService
    private let providerCoordinator: ProviderSettingsCoordinator
    private let modelCoordinator: ModelCatalogCoordinator
    private var lastPersistedSnapshot: AISettingsSnapshot = .default
    private var cancellables: Set<AnyCancellable> = []

    func makeScenarioModelPreferencesViewModel() -> ScenarioModelPreferencesViewModel {
        ScenarioModelPreferencesViewModel(aiConfigCenter: aiConfigCenter)
    }

    init(
        loadUseCase: LoadAISettingsUseCase,
        saveUseCase: SaveAISettingsUseCase,
        localModelService: LocalModelService = LocalModelService(),
        providerModelCatalogService: ProviderModelCatalogService = ProviderModelCatalogService(),
        providerCoordinator: ProviderSettingsCoordinator = ProviderSettingsCoordinator(),
        modelCoordinator: ModelCatalogCoordinator = ModelCatalogCoordinator(),
        ownerAccountIDForLoad: Int64? = nil,
        aiConfigAPI: SparkAIConfigAPI? = nil,
        aiConfigCenter: AIConfigCenter? = nil
    ) {
        self.loadUseCase = loadUseCase
        self.saveUseCase = saveUseCase
        self.ownerAccountIDForLoad = ownerAccountIDForLoad
        self.localModelService = localModelService
        self.providerModelCatalogService = providerModelCatalogService
        self.providerCoordinator = providerCoordinator
        self.modelCoordinator = modelCoordinator
        self.aiConfigAPI = aiConfigAPI
        self.aiConfigCenter = aiConfigCenter
        bindSnapshotChanges()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let loaded: AISettingsSnapshot
        if let aiConfigCenter {
            loaded = await aiConfigCenter.currentSnapshot(ownerAccountID: ownerAccountIDForLoad)
        } else {
            loaded = await loadUseCase.execute(ownerAccountID: ownerAccountIDForLoad)
        }
        lastPersistedSnapshot = loaded
        snapshot = loaded
        hasUnsavedChanges = false
    }

    func save() async {
        guard hasUnsavedChanges else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await performPersistToRepository()
            lastPersistedSnapshot = snapshot
            hasUnsavedChanges = false
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 厂商密钥编辑 Sheet 点「保存」后立即落盘（不等设置页工具栏「保存」）。
    func persistSnapshotNow() async {
        await persistSnapshotNowReturningBool()
    }

    private func performPersistToRepository() async throws {
        try await saveUseCase.execute(snapshot: snapshot, ownerAccountID: ownerAccountIDForLoad)
    }

    func clearError() {
        errorMessage = nil
    }



    func refreshTrialStatus() async {
        guard let aiConfigAPI else { return }
        trialOperationInFlight = true
        defer { trialOperationInFlight = false }
        do {
            let state = try await aiConfigAPI.fetchTrialStatus()
            if snapshot.trial != state {
                snapshot.trial = state
            }
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

    func testProviderConnection(requestURL: String, apiKey: String, model: String) async -> ProviderConnectionTestResult {
        guard let aiConfigAPI else { return ProviderConnectionTestResult(reachable: false, message: nil) }
        do {
            return try await aiConfigAPI.testProviderConnection(
                requestURL: requestURL,
                apiKey: apiKey,
                model: model
            )
        } catch {
            errorMessage = error.localizedDescription
            return ProviderConnectionTestResult(reachable: false, message: error.localizedDescription)
        }
    }

    func fetchRemoteModels(for provider: APIKeys) async throws -> [ProviderRemoteModel] {
        try await providerModelCatalogService.fetchModels(for: provider)
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
        providerID: String? = nil,
        company: String,
        priceTier: Int,
        isHidden: Bool,
        supportsText: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        reasoningControllable: Bool,
        supportsToolUse: Bool,
        supportsImageGen: Bool,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = []
    ) -> AllModels? {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProviderID = AIProviderIdentifier.normalize(providerID ?? co)
        guard baseName.isEmpty == false, baseDisplay.isEmpty == false, co.isEmpty == false else { return nil }
        var uniqueName = baseName
        if snapshot.allModels.contains(where: { $0.name == uniqueName }) {
            uniqueName = baseName + "_" + UUID().uuidString.prefix(8).lowercased()
        }
        var uniqueDisplay = baseDisplay
        if snapshot.allModels.contains(where: { $0.displayName == uniqueDisplay && $0.providerID == resolvedProviderID }) {
            uniqueDisplay = baseDisplay + " (\(UUID().uuidString.prefix(4)))"
        }
        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
        let tier = min(max(priceTier, 0), 3)
        let normalizedToolScenarios = aiToolScenarios.isEmpty ? SparkToolName.all : aiToolScenarios
        let model = AllModels(
            name: uniqueName,
            displayName: uniqueDisplay,
            identity: .model,
            position: position,
            providerID: resolvedProviderID,
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
            reasoningControllable: reasoningControllable,
            aiScenarios: aiScenarios,
            aiToolScenarios: normalizedToolScenarios
        )
        snapshot.allModels.append(model)
        return model
    }

    @discardableResult
    func appendOrRevealRemoteModel(_ remoteModel: ProviderRemoteModel, provider: APIKeys) -> Bool {
        let company = provider.company.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = provider.providerID
        guard company.isEmpty == false, providerID.isEmpty == false else { return false }

        let incomingKey = normalizedRemoteModelKey(remoteModel.name)
        if let index = snapshot.allModels.firstIndex(where: {
            $0.identity == .model &&
            $0.providerID == providerID &&
            normalizedRemoteModelKey($0.name) == incomingKey
        }) {
            snapshot.allModels[index].displayName = remoteModel.displayName
            snapshot.allModels[index].isHidden = false
            snapshot.allModels[index].timestamp = Date()
            return false
        }

        _ = appendOnlineModel(
            name: remoteModel.name,
            displayName: remoteModel.displayName,
            providerID: providerID,
            company: company,
            priceTier: inferredPriceTier(for: remoteModel),
            isHidden: false,
            supportsText: remoteModel.supportsText,
            supportsMultimodal: remoteModel.supportsMultimodal,
            supportsReasoning: remoteModel.supportsReasoning,
            reasoningControllable: remoteModel.supportsReasoning,
            supportsToolUse: remoteModel.supportsToolUse,
            supportsImageGen: remoteModel.supportsImageGen
        )
        return true
    }

    @discardableResult
    func deleteModelAndPersist(id: UUID) async -> Bool {
        do {
            try modelCoordinator.deleteModel(id: id, in: &snapshot)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 替换目录中一条模型（触发 `snapshot` 更新）。
    func replaceModel(_ model: AllModels) {
        guard let idx = snapshot.allModels.firstIndex(where: { $0.id == model.id }) else { return }
        snapshot.allModels[idx] = model
    }

    func replaceAllModels(_ models: [AllModels]) {
        snapshot.allModels = models
    }

    func updateModelPositions(_ positions: [UUID: Int]) {
        for index in snapshot.allModels.indices {
            guard let position = positions[snapshot.allModels[index].id] else { continue }
            snapshot.allModels[index].position = position
        }
    }

    func upsertProvider(_ provider: APIKeys) {
        if let idx = snapshot.apiKeys.firstIndex(where: { $0.id == provider.id }) {
            snapshot.apiKeys[idx] = provider
        } else {
            snapshot.apiKeys.append(provider)
        }
    }

    @discardableResult
    func addProviderAndPersist(_ provider: APIKeys) async -> Bool {
        providerCoordinator.appendProvider(provider, in: &snapshot)
        return await persistSnapshotNowReturningBool()
    }

    @discardableResult
    func setProviderEnabledAndPersist(providerID: UUID, enabled: Bool) async -> Bool {
        do {
            _ = try providerCoordinator.setProviderEnabled(recordID: providerID, enabled: enabled, in: &snapshot)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveProviderFromEditorAndPersist(_ provider: APIKeys) async -> Bool {
        _ = providerCoordinator.saveProviderFromEditor(provider, in: &snapshot)
        return await persistSnapshotNowReturningBool()
    }

    /// 保存按钮触发：先改缓存，再单条落库（模型）。
    @discardableResult
    func replaceModelAndPersist(_ model: AllModels) async -> Bool {
        replaceModel(model)
        return await persistModelNow(modelID: model.id)
    }

    /// 显隐切换：先改缓存，再单条落库（模型）。
    @discardableResult
    func setModelVisibilityAndPersist(modelID: UUID, visible: Bool) async -> Bool {
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == modelID }) else { return false }
        var model = snapshot.allModels[index]
        model.isHidden = !visible
        return await replaceModelAndPersist(model)
    }

    /// 保存按钮触发：先改缓存，再单条落库（厂商）。
    @discardableResult
    func upsertProviderAndPersist(_ provider: APIKeys) async -> Bool {
        upsertProvider(provider)
        return await persistProviderNow(providerID: provider.id)
    }

    /// 新增模型并单条落库（新增时会是 upsert-insert）。
    @discardableResult
    func appendOnlineModelAndPersist(
        name: String,
        displayName: String,
        providerID: String? = nil,
        company: String,
        priceTier: Int,
        isHidden: Bool,
        supportsText: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        reasoningControllable: Bool,
        supportsToolUse: Bool,
        supportsImageGen: Bool,
        aiScenarios: [String] = [],
        aiToolScenarios: [String] = []
    ) async -> Bool {
        guard let model = appendOnlineModel(
            name: name,
            displayName: displayName,
            providerID: providerID,
            company: company,
            priceTier: priceTier,
            isHidden: isHidden,
            supportsText: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            reasoningControllable: reasoningControllable,
            supportsToolUse: supportsToolUse,
            supportsImageGen: supportsImageGen,
            aiScenarios: aiScenarios,
            aiToolScenarios: aiToolScenarios
        ) else {
            return false
        }
        return await persistModelNow(modelID: model.id)
    }

    /// 更新本地智能体（编辑 Sheet 保存）。
    func updateLocalAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String
    ) {
        modelCoordinator.updateLocalAgent(
            id: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            in: &snapshot
        )
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
        for scenario in AIScenario.allCases {
            if snapshot.scenarioDefaultModelName(for: scenario) == model.name {
                snapshot.setScenarioDefaultModelName(nil, for: scenario)
            }
        }
    }

    @discardableResult
    func removeLocalModelAndPersist(_ model: AllModels) async -> Bool {
        do {
            try await removeLocalModel(model)
            return await persistSnapshotNowReturningBool()
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        snapshot.setScenarioDefaultModelName(model.name, for: .chat)
    }

    func hasValidAPIKey(for model: AllModels) -> Bool {
        modelCoordinator.hasValidAPIKey(for: model, in: snapshot)
    }

    func createLocalAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String
    ) {
        modelCoordinator.createLocalAgent(
            displayName: displayName,
            iconSymbol: iconSymbol,
            baseModelName: baseModelName,
            systemPrompt: systemPrompt,
            in: &snapshot
        )
    }

    @discardableResult
    func initializeModelVisibilityAndPersistIfNeeded() async -> Bool {
        guard modelCoordinator.initializeModelVisibility(in: &snapshot) else { return true }
        return await persistSnapshotNowReturningBool()
    }

    private func upsertLocalBaseModel(_ installed: LocalModelInstalled) {
        let localCompany = LocalModelService.localCompany
        if let index = snapshot.allModels.firstIndex(where: { $0.localFilename == installed.fileName && $0.identity == .model }) {
            snapshot.allModels[index].displayName = installed.displayName
            snapshot.allModels[index].name = installed.modelName
            snapshot.allModels[index].providerID = LocalModelService.localProviderID
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
                providerID: LocalModelService.localProviderID,
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

    private func normalizedRemoteModelKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
            .lowercased()
    }

    private func inferredPriceTier(for model: ProviderRemoteModel) -> Int {
        let name = model.name.lowercased()
        if model.supportsImageGen {
            return 3
        }
        if name.contains("nano") || name.contains("mini") || name.contains("flash") || name.contains("lite") {
            return 1
        }
        if name.contains("reasoner") || name.contains("max") || name.contains("opus") || name.contains("pro") {
            return 3
        }
        return 2
    }

    private func bindSnapshotChanges() {
        $snapshot
            .dropFirst()
            .sink { [weak self] latest in
                guard let self else { return }
                self.hasUnsavedChanges = latest != self.lastPersistedSnapshot
            }
            .store(in: &cancellables)

        $snapshot
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] latest in
                guard let self else { return }
                Task { await self.aiConfigCenter?.applyDraftSnapshot(latest) }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    private func persistSnapshotNowReturningBool() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await performPersistToRepository()
            lastPersistedSnapshot = snapshot
            hasUnsavedChanges = false
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistModelNow(modelID: UUID) async -> Bool {
        guard let model = snapshot.allModels.first(where: { $0.id == modelID }) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveUseCase.execute(model: model)
            markPersistedModel(model)
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistProviderNow(providerID: UUID) async -> Bool {
        guard let provider = snapshot.apiKeys.first(where: { $0.id == providerID }) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveUseCase.execute(provider: provider)
            markPersistedProvider(provider)
            hasUnsavedChanges = snapshot != lastPersistedSnapshot
            await aiConfigCenter?.rebuildRuntimeCache(from: snapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func markPersistedModel(_ model: AllModels) {
        if let index = lastPersistedSnapshot.allModels.firstIndex(where: { $0.id == model.id }) {
            lastPersistedSnapshot.allModels[index] = model
        } else {
            lastPersistedSnapshot.allModels.append(model)
        }
    }

    private func markPersistedProvider(_ provider: APIKeys) {
        if let index = lastPersistedSnapshot.apiKeys.firstIndex(where: { $0.id == provider.id }) {
            lastPersistedSnapshot.apiKeys[index] = provider
        } else {
            lastPersistedSnapshot.apiKeys.append(provider)
        }
    }
}
