import Foundation

/// 服务端 STS + 桶信息，供客户端直传 OSS 使用（与 `OCRSTSCredentialsResponse` / file_manager STS 对齐）。
struct AliyunOSSRuntimeConfig: Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
    let bucketName: String
    let region: String
    let endpointURL: String
    /// STS 过期时间（服务端 `expiration` 为 Unix 秒时解析；缺失则视为未知）
    let credentialExpiresAt: Date?

    init?(response: OCRSTSCredentialsResponse) {
        guard !response.accessKeyID.isEmpty, !response.accessKeySecret.isEmpty else { return nil }
        let bucket = response.bucketName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let region = response.region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endpoint = response.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bucket.isEmpty, !region.isEmpty, !endpoint.isEmpty else { return nil }

        self.accessKeyId = response.accessKeyID
        self.accessKeySecret = response.accessKeySecret
        self.securityToken = response.securityToken
        self.bucketName = bucket
        self.region = region
        self.endpointURL = endpoint
        self.credentialExpiresAt = Self.parseExpiration(response.expiration)
    }

    /// 在过期前至少保留 `thresholdSeconds` 秒才视为仍可用。
    func isFresh(thresholdSeconds: TimeInterval) -> Bool {
        guard let exp = credentialExpiresAt else { return true }
        return exp.timeIntervalSinceNow > thresholdSeconds
    }

    private static func parseExpiration(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("-") {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            if let d = fmt.date(from: trimmed) { return d }
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmt.date(from: trimmed) { return d }
        }
        if let unix = Double(trimmed) {
            return Date(timeIntervalSince1970: unix)
        }
        return nil
    }
}
