import Foundation

enum OnboardingStep: Int, CaseIterable, Codable, Equatable, Sendable {
    case welcome = 0
    case profile = 1
    case agent = 2
    case start = 3

    static let activeSteps: [OnboardingStep] = [.welcome, .profile, /*.agent,*/ .start]

    var isSkippable: Bool {
        switch self {
        case .welcome, .profile, .start:
            return false
        case .agent:
            return true
        }
    }

    func next() -> OnboardingStep {
        guard let index = Self.activeSteps.firstIndex(of: self) else { return self }
        return Self.activeSteps[min(index + 1, Self.activeSteps.count - 1)]
    }

    func previous() -> OnboardingStep {
        guard let index = Self.activeSteps.firstIndex(of: self) else { return self }
        return Self.activeSteps[max(index - 1, 0)]
    }
}

struct OnboardingState: Codable, Equatable, Sendable {
    var needsOnboarding: Bool
    var currentStep: OnboardingStep

    static let completed = OnboardingState(needsOnboarding: false, currentStep: .start)
}

protocol OnboardingStateRepository: Sendable {
    func load(accountID: Int64) async -> OnboardingState?
    func save(_ state: OnboardingState, accountID: Int64) async
}
