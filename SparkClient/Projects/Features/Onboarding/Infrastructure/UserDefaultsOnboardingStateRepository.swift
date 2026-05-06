import Foundation

final class UserDefaultsOnboardingStateRepository: OnboardingStateRepository {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(accountID: Int64) async -> OnboardingState? {
        guard let data = defaults.data(forKey: key(accountID: accountID)) else { return nil }
        return try? decoder.decode(OnboardingState.self, from: data)
    }

    func save(_ state: OnboardingState, accountID: Int64) async {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: key(accountID: accountID))
    }

    private func key(accountID: Int64) -> String {
        "spark.onboarding.state.\(accountID)"
    }
}
