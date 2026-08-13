import Combine
import Foundation

@MainActor
final class OnboardingFlowViewModel: ObservableObject {
    @Published var navigationPath: [OnboardingStep] = []

    private let store: OnboardingStore
    private let memberContextStore: MemberContextStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: OnboardingStore, memberContextStore: MemberContextStore) {
        self.store = store
        self.memberContextStore = memberContextStore
        self.navigationPath = Self.navigationPath(for: store.currentStep)

        store.$currentStep
            .removeDuplicates()
            .sink { [weak self] step in
                guard let self else { return }
                let path = Self.navigationPath(for: step)
                if self.navigationPath != path {
                    self.navigationPath = path
                }
            }
            .store(in: &cancellables)
    }

    var currentStep: OnboardingStep {
        navigationPath.last ?? .welcome
    }

    var activeSteps: [OnboardingStep] {
        OnboardingStep.activeSteps
    }

    var canGoNext: Bool {
        switch currentStep {
        case .profile:
            return memberContextStore.context.members.isEmpty == false
        case .welcome, .reportGuide, .medicationGuide, .start:
            return true
        }
    }

    func goNext() {
        guard canGoNext else { return }
        let next = currentStep.next()
        guard next != currentStep else { return }
        if next != .welcome {
            navigationPath.append(next)
        }
        store.updateStep(next)
    }

    func goBack() {
        guard navigationPath.isEmpty == false else { return }
        let previous = currentStep.previous()
        navigationPath.removeLast()
        store.updateStep(previous)
    }

    func skip() {
        guard currentStep.isSkippable else { return }
        goNext()
    }

    func complete() {
        store.complete()
    }

    private static func navigationPath(for step: OnboardingStep) -> [OnboardingStep] {
        guard let index = OnboardingStep.activeSteps.firstIndex(of: step), index > 0 else {
            return []
        }
        return Array(OnboardingStep.activeSteps.dropFirst().prefix(index))
    }
}
