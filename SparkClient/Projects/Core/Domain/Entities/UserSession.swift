import Foundation

struct UserSession: Codable, Equatable, Sendable {
    let profileID: UUID
    let remoteUserID: String?
    let email: String
    let displayName: String
    let signedInAt: Date
}
