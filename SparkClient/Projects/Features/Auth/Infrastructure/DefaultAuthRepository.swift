import Foundation
import UIKit

enum AuthFeatureError: LocalizedError {
    case missingAppleUserIdentifier

    var errorDescription: String? {
        switch self {
        case .missingAppleUserIdentifier:
            return L10n.text("auth.error.apple_user_identifier_missing")
        }
    }
}

/// 认证仓储：
/// 负责桥接远端认证、会话快照存储与本地首屏数据初始化。
final class DefaultAuthRepository: AuthRepository {
    private let backend: Backend
    private let userProfileRepository: any UserProfileRepository
    private let healthMetricsRepository: any HealthMetricsRepository
    private let snapshotStore: SessionSnapshotStore
    private let logger: Logger

    init(
        backend: Backend,
        userProfileRepository: any UserProfileRepository,
        healthMetricsRepository: any HealthMetricsRepository,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.backend = backend
        self.userProfileRepository = userProfileRepository
        self.healthMetricsRepository = healthMetricsRepository
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    func restoreSession() async -> UserSession? {
        guard let session = await snapshotStore.load() else { return nil }

        do {
            // 冷启动先预热 token：若 access 近过期会在这里静默 refresh，
            // 后续业务同步请求可直接拿到最新 Authorization。
            _ = try await backend.tokenProvider().authorizationHeaderValue()
            logger.info("会话恢复成功，认证令牌已就绪", module: .auth)
            return session
        } catch let authError as AuthTokenProviderError {
            // 约束：只有用户主动退出登录时才清理会话。
            // 因此这里不自动回退登录页，保留本地会话并交由后续请求继续自愈。
            logger.warning("会话恢复鉴权异常（保留会话）：\(authError.localizedDescription)", module: .auth)
            return session
        } catch {
            // 网络波动等非认证错误：保留本地会话，允许用户先离线使用。
            logger.warning("会话恢复时 token 预热失败（降级保留会话）：\(error.localizedDescription)", module: .auth)
            return session
        }
    }

    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession {
        let userIdentifier = payload.userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userIdentifier.isEmpty == false else {
            throw AuthFeatureError.missingAppleUserIdentifier
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "SparkClient"
        let deviceID = SparkKeychain.getOrCreateDeviceID()

        let context = try await backend.auth.loginWithApple(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode,
            nonce: payload.nonce,
            user: userIdentifier,
            email: payload.email,
            fullName: payload.fullName,
            bundleId: bundleID,
            deviceId: deviceID
        )

        let normalizedEmail = (payload.email ?? context.email ?? "apple_\(userIdentifier)@privaterelay.appleid.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let displayName = {
            let preferred = payload.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if preferred.isEmpty == false { return preferred }
            let backendName = context.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if backendName.isEmpty == false { return backendName }
            return L10n.text("auth.apple.default_display_name")
        }()

        let signedInAt = Date()
        let profile = try await userProfileRepository.upsertProfile(
            email: normalizedEmail,
            displayName: displayName,
            signedInAt: signedInAt
        )
        try await healthMetricsRepository.seedDefaultMetricsIfNeeded(for: profile.id)

        let session = UserSession(
            profileID: profile.id,
            remoteUserID: backend.deviceCache.currentUserID,
            email: normalizedEmail,
            displayName: displayName,
            signedInAt: signedInAt
        )

        try await snapshotStore.save(session)
        logger.info("用户已通过 Apple 登录，令牌类型=\(context.tokens.tokenType)", module: .auth)
        return session
    }

    func signOut() async throws {
        await backend.tokenProvider().clearTokens()
        backend.deviceCache.clearDeviceMetadata()
        await snapshotStore.clear()
        logger.info("用户已登出", module: .auth)
    }
}
