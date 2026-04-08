import Foundation

/// Aliyun STS payload inside Spark `{ code, msg, data }` (OCR + OSS endpoints share the same shape).
struct OCRSTSCredentialsResponse: Decodable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String
    let securityToken: String?
    /// Normalized for callers: ISO-8601 string from server, or Unix seconds from server as decimal string.
    let expiration: String?
    let bucketName: String?
    let region: String?
    let endpoint: String?

    enum CodingKeys: String, CodingKey {
        case accessKeyID
        case accessKeySecret
        case securityToken
        case expiration
        case accessKeyId = "access_key_id"
        case accessKeySecretSnake = "access_key_secret"
        case securityTokenSnake = "security_token"
        case bucketName = "bucket_name"
        case region
        case endpoint
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
        self.expiration = Self.decodeExpiration(from: container)
        self.bucketName = try? container.decode(String.self, forKey: .bucketName)
        self.region = try? container.decode(String.self, forKey: .region)
        self.endpoint = try? container.decode(String.self, forKey: .endpoint)
    }

    init(
        accessKeyID: String,
        accessKeySecret: String,
        securityToken: String?,
        expiration: String?,
        bucketName: String? = nil,
        region: String? = nil,
        endpoint: String? = nil
    ) {
        self.accessKeyID = accessKeyID
        self.accessKeySecret = accessKeySecret
        self.securityToken = securityToken
        self.expiration = expiration
        self.bucketName = bucketName
        self.region = region
        self.endpoint = endpoint
    }

    private static func decodeExpiration(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let s = try? container.decode(String.self, forKey: .expiration), !s.isEmpty {
            return s
        }
        if let i = try? container.decode(Int64.self, forKey: .expiration) {
            return String(i)
        }
        if let i = try? container.decode(Int.self, forKey: .expiration) {
            return String(i)
        }
        if let d = try? container.decode(Double.self, forKey: .expiration) {
            return String(Int64(d))
        }
        return nil
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
