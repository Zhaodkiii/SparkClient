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

    func requestDeactivation(reason: String = "") async throws -> DeactivationRequestResult {
        struct Payload: Encodable {
            let reason: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Deactivation.Request",
            apiName: "DeactivationAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/deactivation/",
                headers: [:],
                body: .json(AnyEncodable(Payload(reason: reason))),
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
}
