import Foundation

/// 认证域 API。
/// 职责与 purchases-ios 的 Domain API Layer 一致：
/// 只表达业务语义，不关心 URLSession、ETag、重试等细节。
struct SparkAuthAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SparkNetworkEngine) {
        self.configuration = SparkBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    struct LoginResult: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
    }

    struct AuthenticatedUserContext: Sendable {
        let userId: Int
        let email: String?
        let displayName: String?
        let isPro: Bool
        let isNewUser: Bool
        let signInMethod: String?
        let isDeviceAccount: Bool
        let accountResolution: AccountResolution?
        let tokens: AuthTokens
    }

    struct AppleLoginResult: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
        let accountResolution: String?
        let identityScope: String?
    }

    struct DeviceLoginResult: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
        let accountResolution: String?
        let identityScope: String?
    }

    func login(
        identifier: String,
        password: String,
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> AuthTokens {
        nonisolated struct Payload: Encodable {
            let identifier: String
            let password: String
            let bundle_id: String
            let device_id: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Auth.Login",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/password/login/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            identifier: identifier,
                            password: password,
                            bundle_id: bundleId,
                            device_id: deviceId
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "auth.login",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        configuration.logger.debug("认证解码：开始解析密码登录响应为 LoginResult", module: .auth)
        let result = try APIResponseDecoder.decodeWrappedData(LoginResult.self, from: response)
        configuration.logger.info(
            "认证解码：密码登录响应解析成功 userId=\(result.userId) tokenType=\(result.tokenType) expiresIn=\(result.expiresIn)",
            module: .auth
        )

        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.userId))

        return tokens
    }

    func loginWithApple(
        identityToken: String,
        authorizationCode: String?,
        nonce: String?,
        user: String,
        email: String?,
        fullName: String?,
        bundleId: String = "",
        deviceId: String = "",
        deviceSecret: String = ""
    ) async throws -> AuthenticatedUserContext {
        nonisolated struct Payload: Encodable {
            let identity_token: String
            let authorization_code: String?
            let nonce: String?
            let user: String
            let email: String?
            let full_name: String?
            let bundle_id: String
            let device_id: String
            let device_secret: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Auth.AppleLogin",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/apple/login/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            identity_token: identityToken,
                            authorization_code: authorizationCode,
                            nonce: nonce,
                            user: user,
                            email: email,
                            full_name: fullName,
                            bundle_id: bundleId,
                            device_id: deviceId,
                            device_secret: deviceSecret
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "auth.apple.login",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        configuration.logger.debug("认证解码：开始解析 Apple 登录响应为 AppleLoginResult", module: .auth)
        let result = try APIResponseDecoder.decodeWrappedData(AppleLoginResult.self, from: response)
        configuration.logger.info(
            "认证解码：Apple 登录响应解析成功 userId=\(result.userId) resolution=\(result.accountResolution ?? "-") isDeviceAccount=\(result.isDeviceAccount ?? false)",
            module: .auth
        )
        return await makeAuthenticatedContext(
            userId: result.userId,
            email: result.email,
            displayName: result.displayName,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            signInMethod: result.signInMethod ?? "apple",
            isDeviceAccount: result.isDeviceAccount ?? false,
            accountResolution: result.accountResolution,
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresIn: result.expiresIn,
            tokenType: result.tokenType
        )
    }

    func loginWithDevice(
        bundleId: String,
        deviceId: String,
        deviceSecret: String
    ) async throws -> AuthenticatedUserContext {
        nonisolated struct Payload: Encodable {
            let bundle_id: String
            let device_id: String
            let device_secret: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Auth.DeviceLogin",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/device/login/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            bundle_id: bundleId,
                            device_id: deviceId,
                            device_secret: deviceSecret
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "auth.device.login",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let result = try APIResponseDecoder.decodeWrappedData(DeviceLoginResult.self, from: response)
        configuration.logger.info(
            "认证解码：设备登录响应解析成功 userId=\(result.userId) resolution=\(result.accountResolution ?? "-")",
            module: .auth
        )
        return await makeAuthenticatedContext(
            userId: result.userId,
            email: result.email,
            displayName: result.displayName,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            signInMethod: result.signInMethod ?? "device",
            isDeviceAccount: result.isDeviceAccount ?? true,
            accountResolution: result.accountResolution,
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresIn: result.expiresIn,
            tokenType: result.tokenType
        )
    }

    struct TokenRefreshSuccess: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String?
        let tokenType: String?
    }

    func refresh(refreshToken: String) async throws -> AuthTokens {
        nonisolated struct Payload: Encodable {
            let refresh_token: String
            let refresh: String
            let device_id: String
            let bundle_id: String
        }

        let systemInfo = await MainActor.run { SparkSystemInfo.shared }
        let body = Payload(
            refresh_token: refreshToken,
            refresh: refreshToken,
            device_id: systemInfo.installationDeviceID,
            bundle_id: systemInfo.bundleIdentifier
        )

        let operation = CacheableSparkNetworkOperation(
            name: "Auth.Refresh",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/token/refresh/",
                headers: [:],
                body: .json(AnyEncodable(body)),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "auth.refresh",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )

        let response = try await configuration.execute(operation)
        let success = try JSONDecoder.default.decode(TokenRefreshSuccess.self, from: response.data)
        let claims = try JWTExpParser.parseClaims(success.accessToken)

        let tokens = AuthTokens(
            accessToken: success.accessToken,
            refreshToken: success.refreshToken ?? refreshToken,
            expiresAt: claims.expDate,
            tokenType: success.tokenType ?? "Bearer"
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(success.userId))

        return tokens
    }

    /// 冷启动刷新当前账号会话（含最新 `is_pro`），需有效 access token。
    struct CurrentSessionResult: Decodable {
        let userId: Int
        let email: String?
        let displayName: String?
        let isPro: Bool?
        let isNewUser: Bool?
        let signInMethod: String?
        let isDeviceAccount: Bool?
    }

    func logout() async throws {
        let operation = CacheableSparkNetworkOperation(
            name: "Auth.Logout",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/logout/",
                headers: [:],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "auth.logout",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        _ = try await configuration.execute(operation)
        configuration.logger.info("认证：服务端登出成功", module: .auth)
    }

    func fetchCurrentSession() async throws -> CurrentSessionResult {
        let operation = CacheableSparkNetworkOperation(
            name: "Auth.CurrentSession",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/auth/session/",
                headers: [:],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "auth.session.current",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let result = try APIResponseDecoder.decodeWrappedData(CurrentSessionResult.self, from: response)
        configuration.logger.info(
            "认证解码：当前会话刷新成功 userId=\(result.userId) isPro=\(result.isPro ?? false) isDeviceAccount=\(result.isDeviceAccount ?? false)",
            module: .auth
        )
        return result
    }

    private func makeAuthenticatedContext(
        userId: Int,
        email: String?,
        displayName: String?,
        isPro: Bool,
        isNewUser: Bool,
        signInMethod: String?,
        isDeviceAccount: Bool,
        accountResolution: String?,
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String
    ) async -> AuthenticatedUserContext {
        let tokens = AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            tokenType: tokenType
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(userId))
        return AuthenticatedUserContext(
            userId: userId,
            email: email,
            displayName: displayName,
            isPro: isPro,
            isNewUser: isNewUser,
            signInMethod: signInMethod,
            isDeviceAccount: isDeviceAccount,
            accountResolution: AccountResolution(rawValue: accountResolution ?? ""),
            tokens: tokens
        )
    }
}
