import Combine
import Foundation

@MainActor
final class OnboardingFlowViewModel: ObservableObject {
    @Published private(set) var currentStep: OnboardingStep

    private let store: OnboardingStore
    private let memberContextStore: MemberContextStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: OnboardingStore, memberContextStore: MemberContextStore) {
        self.store = store
        self.memberContextStore = memberContextStore
        self.currentStep = store.currentStep

        store.$currentStep
            .removeDuplicates()
            .sink { [weak self] step in
                self?.currentStep = step
            }
            .store(in: &cancellables)
    }

    var activeSteps: [OnboardingStep] {
        OnboardingStep.activeSteps
    }

    var canGoNext: Bool {
        switch currentStep {
        case .profile:
            return memberContextStore.context.members.isEmpty == false
        case .welcome, .agent, .start:
            return true
        }
    }

    func goNext() {
        guard canGoNext else { return }
        store.updateStep(currentStep.next())
    }

    func goBack() {
        store.updateStep(currentStep.previous())
    }

    func skip() {
        guard currentStep.isSkippable else { return }
        store.updateStep(currentStep.next())
    }

    func complete() {
        store.complete()
    }
}
