import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
/// 登录场景状态管理：串联输入校验、用例调用与会话状态更新。
final class LoginViewModel: ObservableObject {
    @Published var isLoading = false

    private let signInWithAppleUseCase: SignInWithAppleUseCase
    private let requestPhoneOTPUseCase: RequestPhoneOTPUseCase
    private let signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase
    private let sessionStore: AppSessionStore
    private let notificationClient: any NotificationClient
    private let logger: Logger = ConsoleLogger()
    private var currentNonce: String?

    private let notificationSource = "auth.login"

    init(
        signInWithAppleUseCase: SignInWithAppleUseCase,
        requestPhoneOTPUseCase: RequestPhoneOTPUseCase,
        signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase,
        sessionStore: AppSessionStore,
        notificationClient: any NotificationClient
    ) {
        self.signInWithAppleUseCase = signInWithAppleUseCase
        self.requestPhoneOTPUseCase = requestPhoneOTPUseCase
        self.signInWithPhoneOTPUseCase = signInWithPhoneOTPUseCase
        self.sessionStore = sessionStore
        self.notificationClient = notificationClient
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
            logger.info("登录流程：Apple credential 已生成 payload，开始执行登录用例", module: .auth)
            let session = try await signInWithAppleUseCase.execute(payload: payload)
            logger.info("登录流程：Apple 登录用例成功返回 session accountID=\(session.accountID)，准备切换 AppSessionStore", module: .auth)
            sessionStore.setAuthenticated(session)
            logger.info("登录流程：AppSessionStore 已切换为已登录 accountID=\(session.accountID)", module: .auth)
            notificationClient.success(
                L10n.text("auth.notification.sign_in_success"),
                source: notificationSource
            )
        } catch {
            if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                logger.info("登录流程：用户取消 Apple 登录", module: .auth)
                notificationClient.info(
                    L10n.text("auth.notification.apple_sign_in_cancelled"),
                    source: notificationSource
                )
                return
            }

            let message = AuthUserFacingErrorMapper.message(for: error, scenario: .appleSignIn)
            logger.error("登录流程：Apple 登录失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
        }
    }

    func sendOTP(phoneNumber: String, isResend: Bool = false) async -> PhoneOTPRequestContext? {
        let scenario: AuthUserFacingErrorMapper.Scenario = isResend ? .phoneOTPResend : .phoneOTPRequest

        do {
            let context = try await requestPhoneOTPUseCase.execute(phoneNumber: phoneNumber)
            let successMessage = isResend
                ? L10n.text("auth.notification.otp_resent")
                : L10n.text("auth.notification.otp_sent")
            notificationClient.success(successMessage, source: notificationSource)
            return context
        } catch {
            let message = AuthUserFacingErrorMapper.message(for: error, scenario: scenario)
            logger.error("登录流程：验证码\(isResend ? "重发" : "发送")失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
            return nil
        }
    }

    func phoneLogin(phoneNumber: String, verificationCode: String, otpId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await signInWithPhoneOTPUseCase.execute(
                phoneNumber: phoneNumber,
                verificationCode: verificationCode,
                otpID: otpId
            )
            logger.info("登录流程：手机号登录用例成功返回 session accountID=\(session.accountID)，准备切换 AppSessionStore", module: .auth)
            sessionStore.setAuthenticated(session)
            logger.info("登录流程：AppSessionStore 已切换为已登录 accountID=\(session.accountID)", module: .auth)
            notificationClient.success(
                L10n.text("auth.notification.sign_in_success"),
                source: notificationSource
            )
        } catch {
            let message = AuthUserFacingErrorMapper.message(for: error, scenario: .phoneOTPLogin)
            logger.error("登录流程：手机号登录失败 error=\(message)", module: .auth)
            notifyFailure(message: message, error: error)
        }
    }

    private func notifyFailure(message: String, error: Error) {
        if AuthUserFacingErrorMapper.isNetworkUnavailable(error) {
            notificationClient.warning(message, source: notificationSource)
        } else {
            notificationClient.error(message, source: notificationSource)
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
