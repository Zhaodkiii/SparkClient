import Foundation

enum OSSConfiguration {
    nonisolated(unsafe) static var endpoint: String = ""
    nonisolated(unsafe) static var bucket: String = ""
    nonisolated(unsafe) static var region: String = ""
    nonisolated static var useSTS: Bool { true }
}

struct OSSCredentials: Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
    let expiration: Date?

    nonisolated var isExpired: Bool {
        guard let expiration else { return false }
        return expiration.timeIntervalSinceNow < 300
    }

    nonisolated var isValid: Bool {
        !accessKeyId.isEmpty && !accessKeySecret.isEmpty && !isExpired
    }
}
