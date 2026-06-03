import Foundation

@MainActor
final class AppBootstrapper {
    private let aiConfigCenter: AIConfigCenter
    private let medicalSyncService: MedicalSyncService
    private let chatSyncSupervisor: ChatSyncSupervisor?
    private let ossConfigurationStore: SparkOSSConfigurationStore
    private let ossAPI: SparkOSSAPI
    private let logger: Logger
    /// 返回 true 表示可继续账号级引导（设备登记未触发鉴权失效）。
    private let requestDeviceRegistration: (DeviceRegistrationReason) async -> Bool
    private let onResetDeviceRegistration: () -> Void

    private var didBootstrapLaunch = false
    private var bootstrappedAccounts: Set<Int64> = []

    init(
        aiConfigCenter: AIConfigCenter,
        medicalSyncService: MedicalSyncService,
        chatSyncSupervisor: ChatSyncSupervisor? = nil,
        ossConfigurationStore: SparkOSSConfigurationStore,
        ossAPI: SparkOSSAPI,
        requestDeviceRegistration: @escaping (DeviceRegistrationReason) async -> Bool = { _ in true },
        onResetDeviceRegistration: @escaping () -> Void = {},
        logger: Logger = ConsoleLogger()
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.medicalSyncService = medicalSyncService
        self.chatSyncSupervisor = chatSyncSupervisor
        self.ossConfigurationStore = ossConfigurationStore
        self.ossAPI = ossAPI
        self.requestDeviceRegistration = requestDeviceRegistration
        self.onResetDeviceRegistration = onResetDeviceRegistration
        self.logger = logger

        NotificationCenter.default.addObserver(
            forName: .aiTrialApplicationResultReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.aiConfigCenter.refreshRemoteConfig()
            }
        }
    }

    func bootstrapAppLaunchIfNeeded() async {
        guard didBootstrapLaunch == false else { return }
        didBootstrapLaunch = true

        // AI 目录进运行时缓存在 `bootstrapIfNeeded(for:)` 中按 `UserSession.accountID` 执行（与 `prepareSignedInSessionIfNeeded` 内 `prewarm` 对齐，避免与随后的运行时重置重复）。
        // 设备登记在会话恢复后由 `AppLifecycleCoordinator` 统一触发（未登录 appLaunch / 已登录 signedInBootstrap），避免先匿名后登录态两次上送。
        logger.info("应用启动引导（设备登记在会话恢复后统一触发）", module: .general)
    }

    /// 账号进入已登录态：DB 目录（仅首次无初始化记录时从 bundle 灌入）→ 本地场景 bundle → 运行时缓存；Pro 再拉 bootstrap 仅进内存。
    func bootstrapIfNeeded(for session: UserSession) async {
        guard bootstrappedAccounts.contains(session.accountID) == false else { return }

        guard await requestDeviceRegistration(.signedInBootstrap) else {
            logger.warning(
                "用户档案 \(session.accountID) 引导中止：设备登记鉴权失效，跳过后续账号级请求",
                module: .general
            )
            return
        }

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
        } catch let error as AIConfigError {
            switch error {
            case .missingModelForScenario(let scenario):
                logger.warning(
                    "AI 启动预热：场景「\(scenario.rawValue)」暂无可用模型，等待 Pro 配置刷新或用户配置",
                    module: .general
                )
            default:
                logger.warning("用户档案引导已结束（降级）：\(error.localizedDescription)", module: .general)
            }
        } catch {
            logger.warning("用户档案引导已结束（降级）：\(error.localizedDescription)", module: .general)
        }
        await chatSyncSupervisor?.kickAttachmentDrain()
    }

    /// 登出等：只清空启动/账号引导去重；真正的账号级状态释放统一交给 `AccountSessionRuntime`。
    /// - Parameter preserveDeviceRegistration: 为 true 时保留匿名冷启动 pending（signedOut 首屏渲染不取消登记）。
    func reset(preserveDeviceRegistration: Bool = false) async {
        didBootstrapLaunch = false
        bootstrappedAccounts.removeAll()
        if preserveDeviceRegistration == false {
            onResetDeviceRegistration()
        }
    }
}
