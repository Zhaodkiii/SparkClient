import Foundation
// import AliyunOSSiOS

final class OSSManager {
    static let shared = OSSManager()

    private(set) var client: OSSClient?
    private var currentCredentials: OSSCredentials?
    var credentialsProvider: (() async throws -> OSSCredentials)?

    private let lock = NSRecursiveLock()
    private var refreshingTask: Task<OSSCredentials, Error>?

    private init() {}

    func updateConfiguration(endpoint: String, bucket: String, region: String) {
        lock.lock()
        OSSConfiguration.endpoint = endpoint
        OSSConfiguration.bucket = bucket
        OSSConfiguration.region = region
        lock.unlock()
    }

    func updateCredentials(_ credentials: OSSCredentials) {
        lock.lock()
        defer { lock.unlock() }
        guard credentials.isValid else { return }

        currentCredentials = credentials
        let credentialProvider = OSSStsTokenCredentialProvider(
            accessKeyId: credentials.accessKeyId,
            secretKeyId: credentials.accessKeySecret,
            securityToken: credentials.securityToken ?? ""
        )
        client = OSSClient(endpoint: OSSConfiguration.endpoint, credentialProvider: credentialProvider)
    }

    func resetRuntimeCredentials() {
        lock.lock()
        currentCredentials = nil
        client = nil
        refreshingTask?.cancel()
        refreshingTask = nil
        lock.unlock()
    }

    func getValidCredentials() async throws -> OSSCredentials {
        lock.lock()
        if let credentials = currentCredentials, !credentials.isExpired {
            lock.unlock()
            return credentials
        }
        if let existingTask = refreshingTask {
            lock.unlock()
            return try await existingTask.value
        }
        guard let provider = credentialsProvider else {
            lock.unlock()
            throw OSSError.credentialsProviderNotSet
        }

        let refreshTask = Task {
            let newCredentials = try await provider()
            updateCredentials(newCredentials)
            lock.lock()
            refreshingTask = nil
            lock.unlock()
            return newCredentials
        }
        refreshingTask = refreshTask
        lock.unlock()
        return try await refreshTask.value
    }

    func ensureInitialized() async throws {
        lock.lock()
        let hasClient = client != nil
        let needsRefresh = currentCredentials?.isExpired ?? true
        lock.unlock()

        if hasClient && !needsRefresh { return }
        _ = try await getValidCredentials()
    }
}

enum OSSError: LocalizedError {
    case credentialsProviderNotSet
    case clientNotInitialized
    case uploadFailed(String)
    case downloadFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .credentialsProviderNotSet:
            return "OSS credentials provider not set"
        case .clientNotInitialized:
            return "OSS client not initialized"
        case .uploadFailed(let message):
            return "OSS upload failed: \(message)"
        case .downloadFailed(let message):
            return "OSS download failed: \(message)"
        case .invalidResponse:
            return "OSS invalid response"
        }
    }
}
