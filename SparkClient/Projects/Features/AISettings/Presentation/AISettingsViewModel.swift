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
            snapshot.chat.model = AISettingsSnapshot.default.chat.model
            snapshot.chat.endpoint = AISettingsSnapshot.default.chat.endpoint
            snapshot.chat.apiKey = nil
        }
    }

    func setChatModel(_ model: AllModels) {
        snapshot.chat.model = model.name
        if model.company.uppercased() == LocalModelService.localCompany {
            snapshot.chat.endpoint = "local://chat/completions"
            snapshot.chat.apiKey = nil
            return
        }

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

        let position = (snapshot.allModels.map(\.position).max() ?? 0) + 1
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
