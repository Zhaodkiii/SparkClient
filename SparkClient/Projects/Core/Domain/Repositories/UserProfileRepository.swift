import Foundation

protocol UserProfileRepository: Sendable {
    func upsertProfile(
        email: String,
        displayName: String,
        isDemo: Bool,
        signedInAt: Date
    ) async throws -> UserProfile

    func fetchProfile(id: UUID) async throws -> UserProfile?
    func fetchLastActiveProfile() async throws -> UserProfile?
}
