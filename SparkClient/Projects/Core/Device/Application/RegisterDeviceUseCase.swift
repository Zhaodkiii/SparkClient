import Foundation

enum RegisterDeviceOutcome: Sendable {
    case succeeded
    case failed
    /// 已登录态但无法取得 Authorization，不降级匿名登记（APP-STARTUP-000006）。
    case skippedMissingAuthenticatedCredentials
    /// 服务端判定鉴权/设备会话失效；`AuthSessionInvalidation` 已由网络层发布（APP-STARTUP-000008）。
    case authSessionInvalidated
}

/// 冷启动 / 登录后 / 推送 token 更新时登记设备（匿名或带 JWT）。
@MainActor
final class RegisterDeviceUseCase {
    private let backend: Backend
    private let logger: Logger

    init(backend: Backend, logger: Logger = ConsoleLogger()) {
        self.backend = backend
        self.logger = logger
    }

    @discardableResult
    func execute(state: DeviceRegistrationState) async -> RegisterDeviceOutcome {
        let pushTokenParam: String? = {
            switch state.pushToken {
            case .unknown:
                return nil
            case .cleared:
                return ""
            case let .value(token):
                return token
            }
        }()

        let requiresAuth: Bool
        if state.isAuthenticated {
            guard backend.deviceCache.currentUserID != nil else {
                logger.warning(
                    "设备登记跳过：已登录态但无缓存用户 ID，不执行匿名降级",
                    module: .network
                )
                return .skippedMissingAuthenticatedCredentials
            }
            do {
                _ = try await backend.tokenProvider().authorizationHeaderValue()
            } catch {
                logger.warning(
                    "设备登记跳过：已登录态无法获取 Authorization，不执行匿名降级，交由鉴权失效流程",
                    module: .network
                )
                return .skippedMissingAuthenticatedCredentials
            }
            requiresAuth = true
        } else {
            requiresAuth = false
        }

        do {
            let result = try await backend.device.registerDevice(
                state: state,
                pushToken: pushTokenParam,
                requiresAuth: requiresAuth
            )
            backend.deviceCache.cache(trustedDeviceID: result.deviceId)
            let idStr = result.id.map(String.init) ?? "-"
            let createdStr: String = {
                guard let c = result.created else { return "-" }
                return c ? "1" : "0"
            }()
            logger.info("设备登记成功 id=\(idStr) created=\(createdStr)", module: .network)
            return .succeeded
        } catch let error as SparkNetworkError {
            if case let .httpError(statusCode, backend, _) = error {
                let backendCode = backend?.code
                let message = backend?.msg ?? ""
                if AuthSessionInvalidation.shouldInvalidate(
                    statusCode: statusCode,
                    backendCode: backendCode,
                    message: message
                ) {
                    logger.warning(
                        "设备登记鉴权失效：\(message)（已交由统一退出流程）",
                        module: .network
                    )
                    return .authSessionInvalidated
                }
            }
            logger.warning("设备登记失败（忽略）: \(error.localizedDescription)", module: .network)
            return .failed
        } catch {
            logger.warning("设备登记失败（忽略）: \(error.localizedDescription)", module: .network)
            return .failed
        }
    }
}
