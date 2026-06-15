import Combine
import Foundation

@MainActor
final class MedicationReminderPreferencesStore: ObservableObject {
    static let shared = MedicationReminderPreferencesStore()

    @Published private(set) var accountID: Int64?
    @Published var showsDrugNameInNotification = false

    private let userDefaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func activate(accountID: Int64) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        showsDrugNameInNotification = userDefaults.bool(forKey: key("showsDrugName"))
        bindPublishers()
    }

    func deactivate() {
        accountID = nil
        cancellables.removeAll()
    }

    private func bindPublishers() {
        cancellables.removeAll()
        $showsDrugNameInNotification
            .dropFirst()
            .sink { [weak self] value in
                guard let self, let accountID else { return }
                userDefaults.set(value, forKey: self.key("showsDrugName"))
            }
            .store(in: &cancellables)
    }

    private func key(_ suffix: String) -> String {
        guard let accountID else { return "spark.medication.reminder.\(suffix)" }
        return "spark.medication.reminder.\(accountID).\(suffix)"
    }
}
