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
        let deactivationId: Int
        let state: String
        let scheduledAt: String?
        let completedAt: String?
    }

    struct DeactivationRequestResult: Decodable {
        let deactivationId: Int
        let state: String
        let scheduledAt: String?
        let immediateDeactivation: Bool?
        let countdownHours: Int?
    }

    struct AccountDeactivationSubmitRequest: Encodable {
        let reason: String?
        let immediateDeactivation: Bool
        let countdownHours: Int?
        let dataRetentionDays: Int?
        let anonymizePersonalData: Bool
        let deleteRelatedData: Bool
        let verification: AccountDeactivationVerification

    }

    enum AccountDeactivationVerification: Encodable {
        case apple(identityToken: String, authorizationCode: String?, userIdentifier: String)
        case phone(otpId: String, code: String)
        case email(otpId: String, code: String)


        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKey.self)
            switch self {
            case .apple(let identityToken, let authorizationCode, let userIdentifier):
                try container.encode("apple", forKey: .key("type"))
                try container.encode(identityToken, forKey: .key("identityToken"))
                try container.encodeIfPresent(authorizationCode, forKey: .key("authorizationCode"))
                try container.encode(userIdentifier, forKey: .key("userIdentifier"))
            case .phone(let otpId, let code):
                try container.encode("phone", forKey: .key("type"))
                try container.encode(otpId, forKey: .key("otpId"))
                try container.encode(code, forKey: .key("code"))
            case .email(let otpId, let code):
                try container.encode("email", forKey: .key("type"))
                try container.encode(otpId, forKey: .key("otpId"))
                try container.encode(code, forKey: .key("code"))
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
