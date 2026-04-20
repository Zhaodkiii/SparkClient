import Foundation

@MainActor
final class AppBootstrapper {
    private let aiConfigCenter: AIConfigCenter
    private let medicalSyncService: MedicalSyncService
    private let syncChatUseCase: SyncChatUseCase?
    private let chatSyncSupervisor: ChatSyncSupervisor?
    private let routeStore: AppRouteStore
    private let ossConfigurationStore: SparkOSSConfigurationStore
    private let ossAPI: SparkOSSAPI
    private let logger: Logger
    private let registerDevice: () async -> Void

    private var didBootstrapLaunch = false
    private var bootstrappedAccounts: Set<Int64> = []

    init(
        aiConfigCenter: AIConfigCenter,
        medicalSyncService: MedicalSyncService,
        syncChatUseCase: SyncChatUseCase? = nil,
        chatSyncSupervisor: ChatSyncSupervisor? = nil,
        routeStore: AppRouteStore,
        ossConfigurationStore: SparkOSSConfigurationStore,
        ossAPI: SparkOSSAPI,
        registerDevice: @escaping () async -> Void = {},
        logger: Logger = ConsoleLogger()
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.medicalSyncService = medicalSyncService
        self.syncChatUseCase = syncChatUseCase
        self.chatSyncSupervisor = chatSyncSupervisor
        self.routeStore = routeStore
        self.ossConfigurationStore = ossConfigurationStore
        self.ossAPI = ossAPI
        self.registerDevice = registerDevice
        self.logger = logger
    }

    func bootstrapAppLaunchIfNeeded() async {
        guard didBootstrapLaunch == false else { return }
        didBootstrapLaunch = true

        // AI 目录进运行时缓存在 `bootstrapIfNeeded(for:)` 中按 `UserSession.accountID` 执行（与 `prepareSignedInSessionIfNeeded` 内 `prewarm` 对齐，避免与随后的运行时重置重复）。
        logger.info("应用启动引导：设备注册等（AI 运行时由已登录引导按账号预热）", module: .general)
        await registerDevice()
    }

    /// 账号进入已登录态：DB 目录（仅首次无初始化记录时从 bundle 灌入）→ 本地场景 bundle → 运行时缓存；Pro 再拉 bootstrap 仅进内存。
    func bootstrapIfNeeded(for session: UserSession) async {
        guard bootstrappedAccounts.contains(session.accountID) == false else { return }
        routeStore.resetForNewSession()

        do {
            await aiConfigCenter.prewarm(ownerAccountID: session.accountID)
            if session.isPro {
                await aiConfigCenter.refreshRemoteConfig()
            }
            await medicalSyncService.bootstrapIfNeeded()
            await ossConfigurationStore.prefetchFromBackend(using: ossAPI)
            for scenario in AIScenario.allCases {
                _ = try await aiConfigCenter.resolve(for: scenario)
            }
            bootstrappedAccounts.insert(session.accountID)
            logger.info("用户档案 \(session.accountID) 引导已完成", module: .general)
        } catch {
            logger.warning("用户档案引导已结束（降级）：\(error.localizedDescription)", module: .general)
        }
        await registerDevice()
        await chatSyncSupervisor?.kickAttachmentDrain()
    }

    /// 登出等：清空引导去重、OSS 缓存、聊天实时连接，并释放 AI 运行时与 Pro overlay（`AIRuntimeConfigStore.reset`）。
    func reset() async {
        didBootstrapLaunch = false
        bootstrappedAccounts.removeAll()
        routeStore.resetForNewSession()
        ossConfigurationStore.clear()
        await syncChatUseCase?.stopRealtime()
        await aiConfigCenter.resetRuntimeCaches()
    }
}
