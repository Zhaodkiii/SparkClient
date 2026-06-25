import Foundation

/// 病例档案拍摄引导页展示记录。
@MainActor
final class CaseDocumentCameraGuideStore {
    static let shared = CaseDocumentCameraGuideStore()

    private let userDefaults: UserDefaults
    private let storageKey = "spark.case_document.camera.guide.has_seen"

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
