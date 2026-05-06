import Foundation

protocol AccountManagementRepository: Sendable {
    func loadAccountProfile(session: UserSession?) async throws -> AccountProfile
    func requestVerification(channel: AccountVerificationChannel) async throws -> AccountVerificationRequestContext
    func submitDeactivation(options: AccountDeactivationOptions, verification: AccountDeactivationVerification) async throws -> AccountDeactivationSubmission
}

