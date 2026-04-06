import Foundation

@MainActor
final class AppBootstrapper {
    private let aiConfigCenter: AIConfigCenter
    private let medicalSyncService: MedicalSyncService
    private let syncChatUseCase: SyncChatUseCase?
    private let routeStore: AppRouteStore
    private let logger: Logger

    private var didBootstrapLaunch = false
    private var bootstrappedProfiles: Set<UUID> = []

    init(
        aiConfigCenter: AIConfigCenter,
        medicalSyncService: MedicalSyncService,
        syncChatUseCase: SyncChatUseCase? = nil,
        routeStore: AppRouteStore,
        logger: Logger = ConsoleLogger()
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.medicalSyncService = medicalSyncService
        self.syncChatUseCase = syncChatUseCase
        self.routeStore = routeStore
        self.logger = logger
    }

    func bootstrapAppLaunchIfNeeded() async {
        guard didBootstrapLaunch == false else { return }
        didBootstrapLaunch = true

        do {
            await aiConfigCenter.refreshRemoteConfig()
            await aiConfigCenter.prewarm()
            for scenario in AIScenario.allCases {
                _ = try await aiConfigCenter.resolve(for: scenario)
            }
            logger.info("应用启动引导已完成", category: "bootstrap")
        } catch {
            logger.warning("应用启动引导已结束（降级）：\(error.localizedDescription)", category: "bootstrap")
        }
    }

    func bootstrapIfNeeded(for session: UserSession) async {
        guard bootstrappedProfiles.contains(session.profileID) == false else { return }
        bootstrappedProfiles.insert(session.profileID)
        routeStore.resetForNewSession()

        do {
            await aiConfigCenter.refreshRemoteConfig()
            await aiConfigCenter.prewarm()
            await medicalSyncService.bootstrapIfNeeded()
            for scenario in AIScenario.allCases {
                _ = try await aiConfigCenter.resolve(for: scenario)
            }
            logger.info("用户档案 \(session.profileID) 引导已完成", category: "bootstrap")
        } catch {
            logger.warning("用户档案引导已结束（降级）：\(error.localizedDescription)", category: "bootstrap")
        }
    }

    func reset() async {
        didBootstrapLaunch = false
        bootstrappedProfiles.removeAll()
        routeStore.resetForNewSession()
        await syncChatUseCase?.stopRealtime()
        await aiConfigCenter.clearRuntimeOverrides()
    }
}
