import Combine
import Foundation

@MainActor
final class OnboardingStore: ObservableObject {
    @Published private(set) var activeAccountID: Int64?
    @Published private(set) var needsOnboarding = false
    @Published private(set) var currentStep: OnboardingStep = .welcome

    private let repository: any OnboardingStateRepository

    init(repository: any OnboardingStateRepository) {
        self.repository = repository
    }

    func activate(session: UserSession) async {
        activeAccountID = session.accountID
        let cached = await repository.load(accountID: session.accountID)

        let state: OnboardingState
        if session.isNewUser {
            state = cached ?? OnboardingState(needsOnboarding: true, currentStep: .welcome)
        } else {
            state = cached ?? .completed
        }

        needsOnboarding = state.needsOnboarding
        currentStep = normalizedStep(state.currentStep)

        if cached == nil, session.isNewUser {
            await repository.save(
                OnboardingState(needsOnboarding: needsOnboarding, currentStep: currentStep),
                accountID: session.accountID
            )
        }
    }

    func deactivate() {
        activeAccountID = nil
        needsOnboarding = false
        currentStep = .welcome
    }

    func updateStep(_ step: OnboardingStep) {
        currentStep = normalizedStep(step)
        persist()
    }

    func complete() {
        needsOnboarding = false
        currentStep = .start
        persist()
    }

    private func normalizedStep(_ step: OnboardingStep) -> OnboardingStep {
        OnboardingStep.activeSteps.contains(step) ? step : .welcome
    }

    private func persist() {
        guard let accountID = activeAccountID else { return }
        let state = OnboardingState(needsOnboarding: needsOnboarding, currentStep: currentStep)
        Task { [repository] in
            await repository.save(state, accountID: accountID)
        }
    }
}
