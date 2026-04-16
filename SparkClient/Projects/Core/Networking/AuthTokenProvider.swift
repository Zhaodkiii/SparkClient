import Foundation
import Security

struct AuthTokens: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
}

enum AuthTokenProviderError: Error, LocalizedError, Sendable, Equatable {
    case missingTokens
    case refreshFailed
    case refreshTemporarilyUnavailable
    case invalidRefreshResponse

    var errorDescription: String? {
        switch self {
        case .missingTokens:
            return "当前未登录或认证信息缺失，请先登录后再重试。"
        case .refreshFailed:
            return "登录状态已过期，令牌刷新失败，请重新登录。"
        case .refreshTemporarilyUnavailable:
            return "当前网络或服务暂不可用，稍后将自动重试令牌刷新。"
        case .invalidRefreshResponse:
            return "服务端返回了无效的令牌刷新结果，请稍后重试。"
        }
    }
}

/// Owns access/refresh tokens and performs refresh de-duping.
actor AuthTokenProvider {
    private let keychainService: String
    private let transport: SparkNetworkTransport
    private let baseURL: URL
    private let logger: Logger

    private let refreshPath: String = "/api/v1/auth/token/refresh/"

    private var cachedTokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?

    init(
        transport: SparkNetworkTransport,
        baseURL: URL,
        keychainService: String = "SparkClient.Auth",
        logger: Logger = ConsoleLogger()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.keychainService = keychainService
        self.logger = logger
    }

    func setTokens(_ tokens: AuthTokens) {
        cachedTokens = tokens
        saveToKeychain(tokens)
    }

    func clearTokens() {
        cachedTokens = nil
        keychainDelete("accessToken")
        keychainDelete("refreshToken")
        keychainDelete("expiresAt")
        keychainDelete("tokenType")
    }

    func authorizationHeaderValue() async throws -> String {
        let tokens = try await validTokens()
        return "\(tokens.tokenType) \(tokens.accessToken)"
    }

    /// Forces a refresh even if current access token is not yet near `expiresAt`.
    /// Used when the server rejects the token (e.g. 401).
    func forceRefreshTokens() async throws -> AuthTokens {
        cachedTokens = nil
        return try await refreshTokensDeDuplicated()
    }

    // MARK: - Refresh / Validity

    private func validTokens() async throws -> AuthTokens {
        if let tokens = cachedTokens {
            if shouldRefresh(tokens: tokens) == false {
                return tokens
            }
            do {
                return try await refreshTokensDeDuplicated()
            } catch let error as AuthTokenProviderError where error == .refreshTemporarilyUnavailable {
                logger.warning("令牌刷新暂不可用，回退使用本地 access token。", module: .auth)
                return tokens
            }
        } else if let tokens = loadFromKeychain() {
            cachedTokens = tokens
            if shouldRefresh(tokens: tokens) == false {
                return tokens
            }
            do {
                return try await refreshTokensDeDuplicated()
            } catch let error as AuthTokenProviderError where error == .refreshTemporarilyUnavailable {
                logger.warning("从 Keychain 恢复后刷新暂不可用，回退使用本地 access token。", module: .auth)
                return tokens
            }
        }

        return try await refreshTokensDeDuplicated()
    }

    private func shouldRefresh(tokens: AuthTokens) -> Bool {
        // Refresh slightly before actual expiry to avoid edge races.
        let skew: TimeInterval = 30
        return Date().addingTimeInterval(skew) >= tokens.expiresAt
    }

    private func refreshTokensDeDuplicated() async throws -> AuthTokens {
        if let existing = refreshTask {
            return try await existing.value
        }

        guard loadRefreshToken() != nil else {
            logger.warning("刷新令牌不存在，无法发起 token refresh。", module: .auth)
            AuthSessionInvalidation.postIfNeeded(
                statusCode: 404,
                backendCode: nil,
                message: "missing_refresh_token",
                source: "AuthTokenProvider.refreshTokensDeDuplicated"
            )
            clearTokens()
            throw AuthTokenProviderError.missingTokens
        }

        let task = Task<AuthTokens, Error> {
            try await self.performRefresh()
        }
        refreshTask = task
        defer {
            // Only the creator reaches this defer; concurrent callers awaited `refreshTask`.
            refreshTask = nil
        }
        return try await task.value
    }

    private func performRefresh() async throws -> AuthTokens {
        guard let refreshToken = loadRefreshToken() else {
            logger.warning("刷新令牌读取失败，判定为未登录态。", module: .auth)
            AuthSessionInvalidation.postIfNeeded(
                statusCode: 404,
                backendCode: nil,
                message: "missing_refresh_token",
                source: "AuthTokenProvider.performRefresh"
            )
            clearTokens()
            throw AuthTokenProviderError.missingTokens
        }

        var urlRequest = URLRequest(url: url(for: refreshPath))
        urlRequest.httpMethod = SparkHTTPMethod.post.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(RequestIdGenerator.make(), forHTTPHeaderField: "X-Request-ID")

        let payload = ["refresh": refreshToken] as [String: String]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        logger.info(SparkNetworkingStrings.Auth.refreshing(), module: .auth)

        let response = try await transport.send(urlRequest)

        // Success shape: { "access": "...", "refresh": "..."? }
        if (200...299).contains(response.httpResponse.statusCode) {
            struct TokenRefreshSuccess: Decodable {
                let access: String
                let refresh: String?
            }

            do {
                let decoder = JSONDecoder()
                let success = try decoder.decode(TokenRefreshSuccess.self, from: response.data)

                let newAccess = success.access
                let newRefresh = success.refresh ?? refreshToken
                let claims = try JWTExpParser.parseClaims(newAccess)
                let tokenType = "Bearer"

                let tokens = AuthTokens(
                    accessToken: newAccess,
                    refreshToken: newRefresh,
                    expiresAt: claims.expDate,
                    tokenType: tokenType
                )
                cachedTokens = tokens
                saveToKeychain(tokens)
                logger.info(SparkNetworkingStrings.Auth.refreshSucceeded(), module: .auth)
                return tokens
            } catch {
                logger.error("令牌刷新响应解析失败：\(error.localizedDescription)", module: .auth)
                throw AuthTokenProviderError.invalidRefreshResponse
            }
        }

        // Error shape fallback: { "code":..., "msg":..., "data":... }
        let statusCode = response.httpResponse.statusCode
        do {
            let backendError = try JSONDecoder().decode(BackendError.self, from: response.data)
            logger.error("令牌刷新 HTTP 错误：code=\(backendError.code) msg=\(backendError.msg)", module: .auth)
        } catch {
            // Ignore; we still throw.
        }

        // 仅在明确的认证失效状态下清理 token；服务异常时保留本地登录态。
        if statusCode == 400 || statusCode == 401 || statusCode == 403 {
            AuthSessionInvalidation.postIfNeeded(
                statusCode: statusCode,
                backendCode: nil,
                message: "token_refresh_failed",
                source: "AuthTokenProvider.performRefresh"
            )
            clearTokens()
            logger.error(SparkNetworkingStrings.Auth.refreshFailed(), module: .auth)
            throw AuthTokenProviderError.refreshFailed
        } else {
            logger.warning("令牌刷新临时失败（HTTP \(statusCode)），保留本地 token。", module: .auth)
            throw AuthTokenProviderError.refreshTemporarilyUnavailable
        }
    }

    private func url(for path: String) -> URL {
        // Absolute paths must preserve a trailing slash: split(separator: "/") drops the
        // final empty segment, which would turn ".../refresh/" into ".../refresh" and
        // trigger Django APPEND_SLASH → 301; URLSession then retries as GET → 405.
        if path.hasPrefix("/"), let resolved = URL(string: path, relativeTo: baseURL) {
            return resolved.absoluteURL
        }
        var url = baseURL
        for segment in path.split(separator: "/") where segment.isEmpty == false {
            url.appendPathComponent(String(segment))
        }
        return url
    }

    // MARK: - Keychain

    private func loadAccessToken() -> String? {
        keychainGet("accessToken")
    }

    private func loadRefreshToken() -> String? {
        keychainGet("refreshToken")
    }

    private func loadFromKeychain() -> AuthTokens? {
        guard
            let accessToken = keychainGet("accessToken"),
            let refreshToken = keychainGet("refreshToken"),
            let tokenType = keychainGet("tokenType"),
            let expiresAtSeconds = keychainGet("expiresAt"),
            let seconds = Double(expiresAtSeconds)
        else { return nil }

        return AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: seconds),
            tokenType: tokenType
        )
    }

    private func saveToKeychain(_ tokens: AuthTokens) {
        keychainSet(tokens.accessToken, "accessToken")
        keychainSet(tokens.refreshToken, "refreshToken")
        keychainSet(String(tokens.expiresAt.timeIntervalSince1970), "expiresAt")
        keychainSet(tokens.tokenType, "tokenType")
    }

    private func keychainSet(_ value: String, _ key: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.warning("Keychain 删除旧 token 失败，key=\(key) status=\(deleteStatus)", module: .auth)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain 持久化 token 失败，key=\(key) status=\(addStatus)", module: .auth)
        } else {
            logger.debug("Keychain 持久化 token 成功，key=\(key)", module: .auth)
        }
    }

    private func keychainGet(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
