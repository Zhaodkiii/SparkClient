import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
/// 登录场景状态管理：串联输入校验、用例调用与会话状态更新。
final class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let signInWithAppleUseCase: SignInWithAppleUseCase
    private let requestPhoneOTPUseCase: RequestPhoneOTPUseCase
    private let signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase
    private let sessionStore: AppSessionStore
    private var currentNonce: String?

    init(
        signInWithAppleUseCase: SignInWithAppleUseCase,
        requestPhoneOTPUseCase: RequestPhoneOTPUseCase,
        signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase,
        sessionStore: AppSessionStore
    ) {
        self.signInWithAppleUseCase = signInWithAppleUseCase
        self.requestPhoneOTPUseCase = requestPhoneOTPUseCase
        self.signInWithPhoneOTPUseCase = signInWithPhoneOTPUseCase
        self.sessionStore = sessionStore
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func signInWithApple(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthViewModelError.invalidAppleCredential
            }

            let payload = try makePayload(from: credential)
            let session = try await signInWithAppleUseCase.execute(payload: payload)
            sessionStore.setAuthenticated(session)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendOTP(phoneNumber: String) async -> PhoneOTPRequestContext? {
        errorMessage = nil
        do {
            return try await requestPhoneOTPUseCase.execute(phoneNumber: phoneNumber)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func phoneLogin(phoneNumber: String, verificationCode: String, otpId: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let session = try await signInWithPhoneOTPUseCase.execute(
                phoneNumber: phoneNumber,
                verificationCode: verificationCode,
                otpID: otpId
            )
            sessionStore.setAuthenticated(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makePayload(from credential: ASAuthorizationAppleIDCredential) throws -> AppleSignInPayload {
        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            identityToken.isEmpty == false
        else {
            throw AuthViewModelError.missingIdentityToken
        }

        let authorizationCode: String?
        if let codeData = credential.authorizationCode {
            authorizationCode = String(data: codeData, encoding: .utf8)
        } else {
            authorizationCode = nil
        }

        return AppleSignInPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: currentNonce,
            userIdentifier: credential.user,
            email: credential.email,
            fullName: Self.displayName(from: credential.fullName)
        )
    }

    private static func displayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let value = PersonNameComponentsFormatter().string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length).lowercased()
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum AuthViewModelError: LocalizedError {
    case invalidAppleCredential
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .invalidAppleCredential:
            return L10n.text("auth.error.apple_credential_invalid")
        case .missingIdentityToken:
            return L10n.text("auth.error.apple_identity_token_missing")
        }
    }
}
