import Foundation

/// 冷启动 / 登录后 / 推送 token 更新时登记设备（匿名或带 JWT）。
@MainActor
final class RegisterDeviceUseCase {
    private let backend: Backend
    private let systemInfo: SparkSystemInfo
    private let logger: Logger

    init(backend: Backend, systemInfo: SparkSystemInfo = SparkSystemInfo(), logger: Logger = ConsoleLogger()) {
        self.backend = backend
        self.systemInfo = systemInfo
        self.logger = logger
    }

    func execute(pushToken: String? = nil, notificationsEnabled: Bool? = nil) async {
        let bundleId = systemInfo.bundleIdentifier
        let deviceId = systemInfo.installationDeviceID

        var requiresAuth = false
        if backend.deviceCache.currentUserID != nil {
            do {
                _ = try await backend.tokenProvider().authorizationHeaderValue()
                requiresAuth = true
            } catch {
                requiresAuth = false
            }
        }

        let userIdInt = backend.deviceCache.currentUserIDInt

        do {
            let result = try await backend.device.registerDevice(
                bundleId: bundleId,
                deviceId: deviceId,
                userId: userIdInt,
                pushToken: pushToken,
                notificationsEnabled: notificationsEnabled,
                systemInfo: systemInfo,
                requiresAuth: requiresAuth
            )
            backend.deviceCache.cache(trustedDeviceID: result.deviceId)
            let idStr = result.id.map(String.init) ?? "-"
            let createdStr: String = {
                guard let c = result.created else { return "-" }
                return c ? "1" : "0"
            }()
            logger.info("设备登记成功 id=\(idStr) created=\(createdStr)", module: .network)
        } catch {
            logger.warning("设备登记失败（忽略）: \(error.localizedDescription)", module: .network)
        }
    }
}
