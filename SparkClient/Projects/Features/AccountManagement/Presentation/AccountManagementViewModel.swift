import Combine
import Foundation

@MainActor
final class AccountManagementViewModel: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var flowState: AccountDeactivationFlowState = .idle
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var errorMessage: String?
    @Published var options = AccountDeactivationOptions()
    @Published var otpCode = ""
    @Published private(set) var resendCountdown = 0

    var requiredConfirmationPhrase: String {
        L10n.text("account_management.deactivation.confirm_phrase", fallback: "删除我的账户")
    }

    private let loadAccountProfileUseCase: LoadAccountProfileUseCase
    private let requestAccountVerificationUseCase: RequestAccountVerificationUseCase
    private let submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase
    private let signOutUseCase: SignOutUseCase
    private let sessionStore: AppSessionStore
    private let memberContextStore: MemberContextStore
    private var countdownTask: Task<Void, Never>?

    init(
        loadAccountProfileUseCase: LoadAccountProfileUseCase,
        requestAccountVerificationUseCase: RequestAccountVerificationUseCase,
        submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase,
        signOutUseCase: SignOutUseCase,
        sessionStore: AppSessionStore,
        memberContextStore: MemberContextStore
    ) {
        self.loadAccountProfileUseCase = loadAccountProfileUseCase
        self.requestAccountVerificationUseCase = requestAccountVerificationUseCase
        self.submitAccountDeactivationUseCase = submitAccountDeactivationUseCase
        self.signOutUseCase = signOutUseCase
        self.sessionStore = sessionStore
        self.memberContextStore = memberContextStore
    }

    var availableVerificationChannels: [AccountVerificationChannel] {
        guard let profile else { return [] }
        switch profile.signInMethod {
        case .apple:
            if let email = profile.email {
                return [.apple, .email(email)]
            }
            return [.apple]
        case .phone:
            if let phone = profile.phoneNumber {
                return [.phone(phone)]
            }
            return []
        }
    }

    func load(session: UserSession) async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            profile = try await loadAccountProfileUseCase.execute(session: session)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginDeactivation() {
        otpCode = ""
        errorMessage = nil
        flowState = .chooseVerification
    }

    func cancelFlow() {
        stopCountdown()
        otpCode = ""
        flowState = .idle
    }

    func requestVerification(_ channel: AccountVerificationChannel) async {
        errorMessage = nil
        otpCode = ""
        switch channel {
        case .apple:
            flowState = .appleReauth
        case .phone, .email:
            do {
                let session: UserSession?
                if case .signedIn(let currentSession) = sessionStore.state {
                    session = currentSession
                } else {
                    session = nil
                }
                let context = try await requestAccountVerificationUseCase.execute(channel: channel, session: session)
                flowState = .enteringOTP(channel, otpID: context.otpID)
                startCountdown(seconds: min(max(context.expiresIn, 30), 120))
            } catch {
                flowState = .failed(error.localizedDescription)
            }
        }
    }

    func completeOTPIfReady() {
        guard otpCode.count == 6 else { return }
        guard case .enteringOTP(let channel, let otpID) = flowState else { return }
        switch channel {
        case .phone:
            stopCountdown()
            flowState = .finalConfirmation(.phone(otpID: otpID, code: otpCode))
        case .email:
            stopCountdown()
            flowState = .finalConfirmation(.email(otpID: otpID, code: otpCode))
        case .apple:
            break
        }
    }

    func completeAppleReauth(identityToken: String, authorizationCode: String?, userIdentifier: String) {
        flowState = .finalConfirmation(
            .apple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier
            )
        )
    }

    func failAppleReauth(_ error: Error) {
        flowState = .failed(error.localizedDescription)
    }

    func submitFinalDeactivation() async {
        guard case .finalConfirmation(let verification) = flowState else {
            flowState = .failed(AccountManagementError.missingVerificationProof.localizedDescription)
            return
        }
        flowState = .submitting
        do {
            let result = try await submitAccountDeactivationUseCase.execute(options: options, verification: verification)
            flowState = .completed(result)
            try await signOutUseCase.execute()
            memberContextStore.clearSessionPersistenceAndReset()
            sessionStore.setSignedOut()
        } catch {
            flowState = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await signOutUseCase.execute()
            memberContextStore.clearSessionPersistenceAndReset()
            sessionStore.setSignedOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func maskedTarget(for channel: AccountVerificationChannel) -> String {
        switch channel {
        case .apple:
            return L10n.text("account_management.target.apple_id", fallback: "Apple ID")
        case .phone(let value):
            let compact = value.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 7 else { return value }
            return "\(compact.prefix(3))****\(compact.suffix(2))"
        case .email(let value):
            guard let at = value.firstIndex(of: "@") else { return value }
            let name = value[..<at]
            let domain = value[at...]
            if name.count <= 3 {
                return "\(name.prefix(1))***\(domain)"
            }
            return "\(name.prefix(2))***\(name.suffix(1))\(domain)"
        }
    }

    private func startCountdown(seconds: Int) {
        stopCountdown()
        resendCountdown = seconds
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.resendCountdown > 0 {
                        self.resendCountdown -= 1
                    }
                    if self.resendCountdown == 0 {
                        self.stopCountdown()
                    }
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        resendCountdown = 0
    }

    deinit {
        countdownTask?.cancel()
    }
}
