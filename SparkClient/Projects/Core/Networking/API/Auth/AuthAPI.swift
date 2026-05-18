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
        let tokens: AuthTokens
    }

    func login(
        identifier: String,
        password: String,
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> AuthTokens {
        struct Payload: Encodable {
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
    }

    func loginWithApple(
        identityToken: String,
        authorizationCode: String?,
        nonce: String?,
        user: String,
        email: String?,
        fullName: String?,
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> AuthenticatedUserContext {
        struct Payload: Encodable {
            let identity_token: String
            let authorization_code: String?
            let nonce: String?
            let user: String
            let email: String?
            let full_name: String?
            let bundle_id: String
            let device_id: String
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
                            device_id: deviceId
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
            "认证解码：Apple 登录响应解析成功 userId=\(result.userId) email=\(result.email ?? "-") isPro=\(result.isPro ?? false) isNewUser=\(result.isNewUser ?? false)",
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

        return AuthenticatedUserContext(
            userId: result.userId,
            email: result.email,
            displayName: result.displayName,
            isPro: result.isPro ?? false,
            isNewUser: result.isNewUser ?? false,
            tokens: tokens
        )
    }

    struct TokenRefreshSuccess: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String?
        let tokenType: String?
    }

    func refresh(refreshToken: String) async throws -> AuthTokens {
        struct Payload: Encodable {
            let refresh_token: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Auth.Refresh",
            apiName: "AuthAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/auth/token/refresh/",
                headers: [:],
                body: .json(AnyEncodable(Payload(refresh_token: refreshToken))),
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
}
