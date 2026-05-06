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

    func requestVerification(channel: AccountVerificationChannel) async throws -> AccountVerificationRequestContext {
        let bundleID = Bundle.main.bundleIdentifier ?? "SparkClient"
        let deviceID = SparkKeychain.getOrCreateDeviceID()

        switch channel {
        case .phone(let phoneNumber):
            let result = try await backend.otp.requestPhoneOTP(
                phoneNumber: phoneNumber,
                bundleId: bundleID,
                deviceId: deviceID
            )
            return AccountVerificationRequestContext(channel: channel, otpID: result.otp_id, expiresIn: result.expires_in)
        case .email(let email):
            let result = try await backend.otp.requestEmailOTP(
                email: email,
                bundleId: bundleID,
                deviceId: deviceID
            )
            return AccountVerificationRequestContext(channel: channel, otpID: result.otp_id, expiresIn: result.expires_in)
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
        case .phone(let otpID, let code):
            apiVerification = .phone(otpID: otpID, code: code)
        case .email(let otpID, let code):
            apiVerification = .email(otpID: otpID, code: code)
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
            deactivationID: result.deactivation_id,
            state: result.state,
            scheduledAt: result.scheduled_at,
            immediateDeactivation: result.immediate_deactivation,
            countdownHours: result.countdown_hours
        )
    }
}

