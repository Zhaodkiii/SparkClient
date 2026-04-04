import Foundation

struct BackendOCRCredentialsProvider: OCRCredentialsProvider {
    let api: SparkOCRAPI

    func fetchAliyunOCRCredentials() async throws -> OCRAliyunCredentials {
        let credentials = try await api.getSTSCredentials()
        return OCRAliyunCredentials(
            accessKeyId: credentials.accessKeyID,
            accessKeySecret: credentials.accessKeySecret,
            securityToken: credentials.securityToken
        )
    }
}
