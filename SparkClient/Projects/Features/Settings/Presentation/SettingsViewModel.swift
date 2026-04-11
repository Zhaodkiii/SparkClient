import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var isSigningOut = false
    @Published private(set) var isSyncing = false
    @Published var syncEnabled = true
    @Published var syncPriority: CloudSyncPriority = .balanced
    @Published private(set) var lastSyncDescription = ""
    @Published private(set) var errorMessage: String?

    private let sessionStore: AppSessionStore
    private let signOutUseCase: SignOutUseCase
    private let medicalSyncService: MedicalSyncService
    private let deviceCache: DeviceCache

    init(
        sessionStore: AppSessionStore,
        signOutUseCase: SignOutUseCase,
        medicalSyncService: MedicalSyncService,
        deviceCache: DeviceCache
    ) {
        self.sessionStore = sessionStore
        self.signOutUseCase = signOutUseCase
        self.medicalSyncService = medicalSyncService
        self.deviceCache = deviceCache
    }

    func clearETagCache() {
        deviceCache.clearETagResponseCache()
    }

    func loadSyncPreference() async {
        let preference = await medicalSyncService.currentPreference()
        syncEnabled = preference.isSyncEnabled
        syncPriority = preference.syncPriority
        if let lastSyncAt = preference.lastSyncAt {
            lastSyncDescription = lastSyncAt.formatted(date: .abbreviated, time: .shortened)
        } else {
            lastSyncDescription = L10n.text("settings.sync.never")
        }
    }

    func updateSyncPriority(_ priority: CloudSyncPriority) async {
        await medicalSyncService.setSyncPriority(priority)
        await loadSyncPreference()
    }

    func updateSyncEnabled(_ enabled: Bool) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await medicalSyncService.setSyncEnabled(enabled)
            await loadSyncPreference()
        } catch {
            syncEnabled.toggle()
            errorMessage = error.localizedDescription
        }
    }

    func triggerSyncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await medicalSyncService.syncNow()
            await loadSyncPreference()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await signOutUseCase.execute()
            sessionStore.setSignedOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
