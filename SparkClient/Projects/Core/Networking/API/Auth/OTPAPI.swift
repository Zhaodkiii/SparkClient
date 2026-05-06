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
        let otp_id: String
        let expires_in: Int
    }

    struct OTPVerifyResult: Decodable {
        let user_id: Int
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let token_type: String
        let otp_id: String
    }

    struct PhoneOTPVerifyResult: Decodable {
        let user_id: Int
        let phone_number: String
        let display_name: String?
        let is_pro: Bool?
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let token_type: String
        let otp_id: String
        let is_new_user: Bool?
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
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in)),
            tokenType: result.token_type
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.user_id))

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
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in)),
            tokenType: result.token_type
        )
        await configuration.engine.tokenProvider().setTokens(tokens)
        configuration.deviceCache.cache(currentUserID: Int64(result.user_id))

        return result
    }
}
