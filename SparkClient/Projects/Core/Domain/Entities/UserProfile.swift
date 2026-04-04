import Foundation

struct UserProfile: Equatable, Sendable {
    let id: UUID
    let email: String
    let displayName: String
    let isDemo: Bool
    let createdAt: Date
    let lastSignedInAt: Date
}
