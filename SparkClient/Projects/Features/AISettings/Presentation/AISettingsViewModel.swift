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

    private let loadUseCase: LoadAISettingsUseCase
    private let saveUseCase: SaveAISettingsUseCase
    private var lastPersistedSnapshot: AISettingsSnapshot = .default
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadUseCase: LoadAISettingsUseCase,
        saveUseCase: SaveAISettingsUseCase
    ) {
        self.loadUseCase = loadUseCase
        self.saveUseCase = saveUseCase
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
