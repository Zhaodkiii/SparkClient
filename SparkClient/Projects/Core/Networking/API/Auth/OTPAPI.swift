import Foundation

/// OTP 域 API。
struct SparkOTPAPI {
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

    struct OTPRequestResult: Decodable {
        let otpId: String
        let expiresIn: Int
    }

    struct OTPVerifyResult: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let otpId: String
    }

    struct PhoneOTPVerifyResult: Decodable {
        let userId: Int
        let phoneNumber: String
        let displayName: String?
        let isPro: Bool?
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let tokenType: String
        let otpId: String
        let isNewUser: Bool?
    }

    func requestEmailOTP(
        email: String,
        providerUID: String = "",
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> OTPRequestResult {
        struct Payload: Encodable {
            let email: String
            let provider_uid: String
            let bundle_id: String
            let device_id: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "OTP.RequestEmail",
            apiName: "OTPAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/otp/email/request/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            email: email,
                            provider_uid: providerUID,
                            bundle_id: bundleId,
                            device_id: deviceId
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "otp.email.request",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(OTPRequestResult.self, from: response)
    }

    func verifyEmailOTP(
        otpId: String,
        email: String,
        code: String,
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> AuthTokens {
        struct Payload: Encodable {
            let otp_id: String
            let email: String
            let code: String
            let bundle_id: String
            let device_id: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "OTP.VerifyEmail",
            apiName: "OTPAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/otp/email/verify/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            otp_id: otpId,
                            email: email,
                            code: code,
                            bundle_id: bundleId,
                            device_id: deviceId
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "otp.email.verify",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )

        let response = try await configuration.execute(operation)
        let result = try APIResponseDecoder.decodeWrappedData(OTPVerifyResult.self, from: response)

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

    func requestPhoneOTP(
        phoneNumber: String,
        providerUID: String = "",
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> OTPRequestResult {
        struct Payload: Encodable {
            let phone_number: String
            let provider_uid: String
            let bundle_id: String
            let device_id: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "OTP.RequestPhone",
            apiName: "OTPAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/otp/phone/request/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            phone_number: phoneNumber,
                            provider_uid: providerUID,
                            bundle_id: bundleId,
                            device_id: deviceId
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "otp.phone.request",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(OTPRequestResult.self, from: response)
    }

    func verifyPhoneOTP(
        otpId: String,
        phoneNumber: String,
        code: String,
        bundleId: String = "",
        deviceId: String = ""
    ) async throws -> PhoneOTPVerifyResult {
        struct Payload: Encodable {
            let otp_id: String
            let phone_number: String
            let code: String
            let bundle_id: String
            let device_id: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "OTP.VerifyPhone",
            apiName: "OTPAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/otp/phone/verify/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            otp_id: otpId,
                            phone_number: phoneNumber,
                            code: code,
                            bundle_id: bundleId,
                            device_id: deviceId
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "otp.phone.verify",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )

        let response = try await configuration.execute(operation)
        let result = try APIResponseDecoder.decodeWrappedData(PhoneOTPVerifyResult.self, from: response)

        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.userId))

        return result
    }
}
