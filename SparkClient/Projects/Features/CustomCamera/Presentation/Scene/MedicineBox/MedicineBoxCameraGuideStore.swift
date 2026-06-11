import Foundation

/// 药箱拍摄引导页展示记录（UserDefaults 持久化，与饮食识别引导互不影响）。
@MainActor
final class MedicineBoxCameraGuideStore {
    static let shared = MedicineBoxCameraGuideStore()

    private let userDefaults: UserDefaults
    private let storageKey = "spark.medicine_box.camera.guide.has_seen"

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
