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


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        self.accessKeyID =
            (try? container.decode(String.self, forKey: .key("accessKeyId"))) ??
            (try? container.decode(String.self, forKey: .key("accessKeyId"))) ?? ""
        self.accessKeySecret =
            (try? container.decode(String.self, forKey: .key("accessKeySecret"))) ??
            (try? container.decode(String.self, forKey: .key("accessKeySecret"))) ?? ""
        self.securityToken =
            (try? container.decode(String.self, forKey: .key("securityToken"))) ??
            (try? container.decode(String.self, forKey: .key("securityToken")))
        self.expiration = Self.decodeExpiration(from: container)
        self.bucketName = try? container.decode(String.self, forKey: .key("bucketName"))
        self.region = try? container.decode(String.self, forKey: .key("region"))
        self.endpoint = try? container.decode(String.self, forKey: .key("endpoint"))
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

    private static func decodeExpiration(from container: KeyedDecodingContainer<CodableKey>) -> String? {
        if let s = try? container.decode(String.self, forKey: .key("expiration")), !s.isEmpty {
            return s
        }
        if let i = try? container.decode(Int64.self, forKey: .key("expiration")) {
            return String(i)
        }
        if let i = try? container.decode(Int.self, forKey: .key("expiration")) {
            return String(i)
        }
        if let d = try? container.decode(Double.self, forKey: .key("expiration")) {
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
