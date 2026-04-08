import Foundation

/// Authenticated Aliyun OSS STS (same `data` shape as OCR STS).
struct SparkOSSAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    func getSTSCredentials() async throws -> OCRSTSCredentialsResponse {
        let operation = CacheableSparkNetworkOperation(
            name: "OSS.STS",
            apiName: "OSSAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/oss/sts/credentials/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "oss.sts.credentials",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(OCRSTSCredentialsResponse.self, from: response)
    }
}
