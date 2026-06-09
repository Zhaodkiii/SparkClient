import Combine
import Foundation

/// 首页饮食营养入口展示偏好（UserDefaults 持久化）。
@MainActor
final class HomeNutritionEntryPreferencesStore: ObservableObject {
    static let shared = HomeNutritionEntryPreferencesStore()

    @Published var displayMode: HomeNutritionEntryDisplayMode {
        didSet {
            guard displayMode != oldValue else { return }
            userDefaults.set(displayMode.rawValue, forKey: storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "spark.home.nutrition.entry.display_mode"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: storageKey),
           let mode = HomeNutritionEntryDisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .compact
        }
    }
}
