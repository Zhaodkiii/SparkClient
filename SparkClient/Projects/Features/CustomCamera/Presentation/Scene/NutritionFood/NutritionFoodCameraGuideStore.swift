import Foundation

/// 饮食识别相机引导页展示记录（UserDefaults 持久化）。
@MainActor
final class NutritionFoodCameraGuideStore {
    static let shared = NutritionFoodCameraGuideStore()

    private let userDefaults: UserDefaults
    private let storageKey = "spark.nutrition.food_camera.guide.has_seen"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasSeenGuide: Bool {
        userDefaults.bool(forKey: storageKey)
    }

    func markAsSeen() {
        userDefaults.set(true, forKey: storageKey)
    }
}
