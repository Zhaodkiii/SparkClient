import Foundation

/// 医疗报告拍摄引导页展示记录。
@MainActor
final class ExaminationReportCameraGuideStore {
    static let shared = ExaminationReportCameraGuideStore()

    private let userDefaults: UserDefaults
    private let storageKey = "spark.examination_report.camera.guide.has_seen"

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
