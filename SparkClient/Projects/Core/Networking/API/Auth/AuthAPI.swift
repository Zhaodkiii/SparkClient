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
        let user_id: Int
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let token_type: String
    }

    struct AuthenticatedUserContext: Sendable {
        let userID: Int
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
        let result = try APIResponseDecoder.decodeWrappedData(LoginResult.self, from: response)

        let tokens = AuthTokens(
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in)),
            tokenType: result.token_type
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.user_id))

        return tokens
    }

    struct AppleLoginResult: Decodable {
        let user_id: Int
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let token_type: String
        let email: String?
        let display_name: String?
        let is_pro: Bool?
        let is_new_user: Bool?
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
        let result = try APIResponseDecoder.decodeWrappedData(AppleLoginResult.self, from: response)
        let tokens = AuthTokens(
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in)),
            tokenType: result.token_type
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.user_id))

        return AuthenticatedUserContext(
            userID: result.user_id,
            email: result.email,
            displayName: result.display_name,
            isPro: result.is_pro ?? false,
            isNewUser: result.is_new_user ?? false,
            tokens: tokens
        )
    }

    struct TokenRefreshSuccess: Decodable {
        let user_id: Int
        let access_token: String
        let refresh_token: String?
        let token_type: String?
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
        let success = try JSONDecoder().decode(TokenRefreshSuccess.self, from: response.data)
        let claims = try JWTExpParser.parseClaims(success.access_token)

        let tokens = AuthTokens(
            accessToken: success.access_token,
            refreshToken: success.refresh_token ?? refreshToken,
            expiresAt: claims.expDate,
            tokenType: success.token_type ?? "Bearer"
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(success.user_id))

        return tokens
    }
}
