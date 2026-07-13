import Foundation

final class DefaultAccountManagementRepository: AccountManagementRepository {
    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func loadAccountProfile(session: UserSession?) async throws -> AccountProfile {
        guard let session else {
            throw AccountManagementError.missingSession
        }
        return AccountProfile(
            accountID: session.accountID,
            displayName: session.displayName,
            contact: session.email,
            signInMethod: session.signInMethod,
            signedInAt: session.signedInAt,
            isPro: session.isPro
        )
    }

    func requestVerification(channel: AccountVerificationChannel, session: UserSession?) async throws -> AccountVerificationRequestContext {
        let bundleId = Bundle.main.bundleIdentifier ?? "SparkClient"
        let deviceId = SparkKeychain.getOrCreateDeviceID()

        switch channel {
        case .phone(let phoneNumber):
            guard let session else {
                throw AccountManagementError.missingSession
            }
            let result = try await backend.otp.requestPhoneOTP(
                phoneNumber: phoneNumber,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: "account_deactivation",
                userId: Int(session.accountID)
            )
            return AccountVerificationRequestContext(channel: channel, otpID: result.otpId, expiresIn: result.expiresIn)
        case .email(let email):
            let result = try await backend.otp.requestEmailOTP(
                email: email,
                bundleId: bundleId,
                deviceId: deviceId,
                scene: "login"
            )
            return AccountVerificationRequestContext(channel: channel, otpID: result.otpId, expiresIn: result.expiresIn)
        case .apple:
            throw AccountManagementError.unsupportedVerificationChannel
        }
    }

    func submitDeactivation(options: AccountDeactivationOptions, verification: AccountDeactivationVerification) async throws -> AccountDeactivationSubmission {
        let apiVerification: SparkDeactivationAPI.AccountDeactivationVerification
        switch verification {
        case .apple(let identityToken, let authorizationCode, let userIdentifier):
            apiVerification = .apple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier
            )
        case .phone(let otpId, let code):
            apiVerification = .phone(otpId: otpId, code: code)
        case .email(let otpId, let code):
            apiVerification = .email(otpId: otpId, code: code)
        }

        let request = SparkDeactivationAPI.AccountDeactivationSubmitRequest(
            reason: options.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : options.reason,
            immediateDeactivation: options.immediateDeactivation,
            countdownHours: options.immediateDeactivation ? nil : options.countdownHours,
            dataRetentionDays: options.dataRetentionDays,
            anonymizePersonalData: options.anonymizePersonalData,
            deleteRelatedData: options.deleteRelatedData,
            verification: apiVerification
        )
        let result = try await backend.deactivation.submitAccountDeactivation(request)
        return AccountDeactivationSubmission(
            deactivationID: result.deactivationId,
            state: result.state,
            scheduledAt: result.scheduledAt,
            immediateDeactivation: result.immediateDeactivation,
            countdownHours: result.countdownHours
        )
    }
}
