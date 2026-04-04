import Foundation

struct OCRSTSCredentialsResponse: Decodable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String
    let securityToken: String?
    let expiration: String?

    enum CodingKeys: String, CodingKey {
        case accessKeyID
        case accessKeySecret
        case securityToken
        case expiration
        case accessKeyId = "access_key_id"
        case accessKeySecretSnake = "access_key_secret"
        case securityTokenSnake = "security_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessKeyID =
            (try? container.decode(String.self, forKey: .accessKeyID)) ??
            (try? container.decode(String.self, forKey: .accessKeyId)) ?? ""
        self.accessKeySecret =
            (try? container.decode(String.self, forKey: .accessKeySecret)) ??
            (try? container.decode(String.self, forKey: .accessKeySecretSnake)) ?? ""
        self.securityToken =
            (try? container.decode(String.self, forKey: .securityToken)) ??
            (try? container.decode(String.self, forKey: .securityTokenSnake))
        self.expiration = try? container.decode(String.self, forKey: .expiration)
    }

    init(accessKeyID: String, accessKeySecret: String, securityToken: String?, expiration: String?) {
        self.accessKeyID = accessKeyID
        self.accessKeySecret = accessKeySecret
        self.securityToken = securityToken
        self.expiration = expiration
    }
}

struct SparkOCRAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    func getSTSCredentials() async throws -> OCRSTSCredentialsResponse {
        let operation = CacheableSparkNetworkOperation(
            name: "OCR.STS",
            apiName: "OCRAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/oss/ocr/sts/credentials/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "ocr.sts.credentials",
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
