import Foundation
// import AliyunOSSiOS

nonisolated final class OSSManager: @unchecked Sendable {
    static let shared = OSSManager()

    private(set) var client: OSSClient?
    private var currentCredentials: OSSCredentials?
    var credentialsProvider: (@Sendable () async throws -> OSSCredentials)?

    private let lock = NSRecursiveLock()
    private var refreshingTask: Task<OSSCredentials, Error>?

    private init() {}

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func updateConfiguration(endpoint: String, bucket: String, region: String) {
        withLock {
            OSSConfiguration.endpoint = endpoint
            OSSConfiguration.bucket = bucket
            OSSConfiguration.region = region
        }
    }

    func updateCredentials(_ credentials: OSSCredentials) {
        withLock {
            guard credentials.isValid else { return }

            currentCredentials = credentials
            let credentialProvider = OSSStsTokenCredentialProvider(
                accessKeyId: credentials.accessKeyId,
                secretKeyId: credentials.accessKeySecret,
                securityToken: credentials.securityToken ?? ""
            )
            client = OSSClient(endpoint: OSSConfiguration.endpoint, credentialProvider: credentialProvider)
        }
    }

    func resetRuntimeCredentials() {
        withLock {
            currentCredentials = nil
            client = nil
            refreshingTask?.cancel()
            refreshingTask = nil
        }
    }

    func getValidCredentials() async throws -> OSSCredentials {
        enum CredentialResolution {
            case ready(OSSCredentials)
            case refresh(Task<OSSCredentials, Error>)
        }

        let resolution = try withLock { () throws -> CredentialResolution in
            if let credentials = currentCredentials, !credentials.isExpired {
                return .ready(credentials)
            }
            if let existingTask = refreshingTask {
                return .refresh(existingTask)
            }
            guard let provider = credentialsProvider else {
                throw OSSError.credentialsProviderNotSet
            }

            let refreshTask = Task { [weak self] in
                let newCredentials = try await provider()
                self?.updateCredentials(newCredentials)
                self?.withLock {
                    self?.refreshingTask = nil
                }
                return newCredentials
            }
            refreshingTask = refreshTask
            return .refresh(refreshTask)
        }

        switch resolution {
        case let .ready(credentials):
            return credentials
        case let .refresh(task):
            return try await task.value
        }
    }

    func ensureInitialized() async throws {
        let (hasClient, needsRefresh) = withLock {
            (client != nil, currentCredentials?.isExpired ?? true)
        }

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
