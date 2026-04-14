import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var isSigningOut = false
    @Published private(set) var isSyncing = false
    @Published var syncEnabled = true
    @Published var syncPriority: CloudSyncPriority = .balanced
    @Published private(set) var lastSyncDescription = ""
    @Published private(set) var deactivationStatusDescription = ""
    @Published private(set) var deactivationId: Int?
    @Published private(set) var isRequestingDeactivation = false
    @Published private(set) var errorMessage: String?

    private let sessionStore: AppSessionStore
    private let signOutUseCase: SignOutUseCase
    private let memberContextStore: MemberContextStore
    private let medicalSyncService: MedicalSyncService
    private let deviceCache: DeviceCache
    private let backend: Backend

    init(
        sessionStore: AppSessionStore,
        signOutUseCase: SignOutUseCase,
        memberContextStore: MemberContextStore,
        medicalSyncService: MedicalSyncService,
        deviceCache: DeviceCache,
        backend: Backend
    ) {
        self.sessionStore = sessionStore
        self.signOutUseCase = signOutUseCase
        self.memberContextStore = memberContextStore
        self.medicalSyncService = medicalSyncService
        self.deviceCache = deviceCache
        self.backend = backend
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
        await refreshDeactivationStatus()
    }

    func refreshDeactivationStatus() async {
        guard let id = deactivationId else {
            deactivationStatusDescription = L10n.text("settings.deactivation.status.none")
            return
        }
        do {
            let status = try await backend.deactivation.getDeactivationStatus(deactivationId: id)
            if let status {
                deactivationStatusDescription = status.state
            } else {
                deactivationStatusDescription = L10n.text("settings.deactivation.status.none")
                deactivationId = nil
            }
        } catch {
            deactivationStatusDescription = L10n.text("settings.deactivation.status.query_failed")
        }
    }

    func requestDeactivation(reason: String = "") async {
        isRequestingDeactivation = true
        defer { isRequestingDeactivation = false }
        do {
            let result = try await backend.deactivation.requestDeactivation(reason: reason)
            deactivationId = result.deactivation_id
            deactivationStatusDescription = result.state
        } catch {
            errorMessage = error.localizedDescription
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
            memberContextStore.clearSessionPersistenceAndReset()
            sessionStore.setSignedOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
