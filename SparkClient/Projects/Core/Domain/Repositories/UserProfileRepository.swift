import Foundation

protocol UserProfileRepository: Sendable {
    func upsertProfile(
        accountID: Int64,
        email: String,
        displayName: String,
        signedInAt: Date,
        signInMethod: UserSession.SignInMethod
    ) async throws -> UserProfile

    func fetchProfile(id: Int64) async throws -> UserProfile?
    func fetchLastActiveProfile() async throws -> UserProfile?
}
