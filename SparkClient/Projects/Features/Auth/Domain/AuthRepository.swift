import Foundation

struct AppleSignInPayload: Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String?
    let userIdentifier: String
    let email: String?
    let fullName: String?
}

protocol AuthRepository: Sendable {
    func restoreSession() async -> UserSession?
    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession
    func signOut() async throws
}
