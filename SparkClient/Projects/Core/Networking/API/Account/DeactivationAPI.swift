import Foundation

/// 注销/销户域 API。
struct SparkDeactivationAPI {
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

    struct DeactivationStatus: Decodable {
        let deactivation_id: Int
        let state: String
        let scheduled_at: String?
        let completed_at: String?
    }

    struct DeactivationRequestResult: Decodable {
        let deactivation_id: Int
        let state: String
        let scheduled_at: String?
        let immediate_deactivation: Bool?
        let countdown_hours: Int?
    }

    struct AccountDeactivationSubmitRequest: Encodable {
        let reason: String?
        let immediateDeactivation: Bool
        let countdownHours: Int?
        let dataRetentionDays: Int?
        let anonymizePersonalData: Bool
        let deleteRelatedData: Bool
        let verification: AccountDeactivationVerification

        enum CodingKeys: String, CodingKey {
            case reason
            case immediateDeactivation = "immediate_deactivation"
            case countdownHours = "countdown_hours"
            case dataRetentionDays = "data_retention_days"
            case anonymizePersonalData = "anonymize_personal_data"
            case deleteRelatedData = "delete_related_data"
            case verification
        }
    }

    enum AccountDeactivationVerification: Encodable {
        case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)
        case phone(otpID: String, code: String)
        case email(otpID: String, code: String)

        enum CodingKeys: String, CodingKey {
            case type
            case identityToken = "identity_token"
            case authorizationCode = "authorization_code"
            case userIdentifier = "user_identifier"
            case otpID = "otp_id"
            case code
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .apple(let identityToken, let authorizationCode, let userIdentifier):
                try container.encode("apple", forKey: .type)
                try container.encode(identityToken, forKey: .identityToken)
                try container.encodeIfPresent(authorizationCode, forKey: .authorizationCode)
                try container.encode(userIdentifier, forKey: .userIdentifier)
            case .phone(let otpID, let code):
                try container.encode("phone", forKey: .type)
                try container.encode(otpID, forKey: .otpID)
                try container.encode(code, forKey: .code)
            case .email(let otpID, let code):
                try container.encode("email", forKey: .type)
                try container.encode(otpID, forKey: .otpID)
                try container.encode(code, forKey: .code)
            }
        }
    }

    func getDeactivationStatus(deactivationId: Int) async throws -> DeactivationStatus? {
        let operation = CacheableSparkNetworkOperation(
            name: "Deactivation.GetStatus",
            apiName: "DeactivationAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/deactivation/",
                queryItems: [URLQueryItem(name: "deactivation_id", value: "\(deactivationId)")],
                headers: [:],
                body: .none,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "deactivation.status.\(deactivationId)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: 60
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(DeactivationStatus?.self, from: response)
    }

    func requestDeactivation(
        reason: String = "",
        immediateDeactivation: Bool = true,
        countdownHours: Int = 24
    ) async throws -> DeactivationRequestResult {
        struct Payload: Encodable {
            let reason: String
            let immediate_deactivation: Bool
            let countdown_hours: Int
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Deactivation.Request",
            apiName: "DeactivationAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/deactivation/",
                headers: [:],
                body: .json(
                    AnyEncodable(
                        Payload(
                            reason: reason,
                            immediate_deactivation: immediateDeactivation,
                            countdown_hours: countdownHours
                        )
                    )
                ),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "deactivation.request",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(DeactivationRequestResult.self, from: response)
    }

    func submitAccountDeactivation(_ request: AccountDeactivationSubmitRequest) async throws -> DeactivationRequestResult {
        let operation = CacheableSparkNetworkOperation(
            name: "Deactivation.SubmitVerified",
            apiName: "DeactivationAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/deactivation/",
                headers: [:],
                body: .json(AnyEncodable(request)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "deactivation.submit.verified",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(DeactivationRequestResult.self, from: response)
    }

    func cancelDeactivation(deactivationId: Int, reason: String = "") async throws -> DeactivationRequestResult {
        struct Payload: Encodable {
            let reason: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Deactivation.Cancel",
            apiName: "DeactivationAPI",
            request: SparkNetworkRequest(
                method: .delete,
                path: "/api/v1/deactivation/",
                queryItems: [URLQueryItem(name: "deactivation_id", value: "\(deactivationId)")],
                headers: [:],
                body: .json(AnyEncodable(Payload(reason: reason))),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "deactivation.cancel.\(deactivationId)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(DeactivationRequestResult.self, from: response)
    }
}
