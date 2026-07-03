import Foundation

/// 医疗公开分享 API：病例详情页调用，用于创建 10 天有效的 Web 分享记录。
struct SparkMedicalShareAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    struct CreateSharePayload: Encodable, Sendable {
        let businessType: String
        let businessId: Int
    }

    struct CreateShareResponse: Decodable, Sendable {
        let shareCode: String
        let shareUrl: String
        let businessType: String
        let businessId: Int
        let expiresAt: Date
        let status: String
    }

    func createShare(businessType: String, businessID: Int) async throws -> CreateShareResponse {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/shares/",
            body: CreateSharePayload(businessType: businessType, businessId: businessID),
            responseType: CreateShareResponse.self
        )
    }

    func createMedicalCaseShare(caseID: Int) async throws -> CreateShareResponse {
        try await createShare(businessType: "medical_case", businessID: caseID)
    }

    private func postRequest<T: Decodable, B: Encodable>(
        method: SparkHTTPMethod,
        path: String,
        body: B?,
        responseType: T.Type
    ) async throws -> T {
        let sparkBody: SparkBody = {
            guard let body else { return .none }
            return .json(AnyEncodable(body))
        }()
        let op = CacheableSparkNetworkOperation(
            name: "Medical.Share.\(path)",
            apiName: "SparkMedicalShareAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                body: sparkBody,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.share.\(path)",
                    retryConfig: .default,
                    isIdempotent: method == .get,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(op)
        return try APIResponseDecoder.decodeWrappedData(T.self, from: response, decoder: .medicalAPI)
    }
}
