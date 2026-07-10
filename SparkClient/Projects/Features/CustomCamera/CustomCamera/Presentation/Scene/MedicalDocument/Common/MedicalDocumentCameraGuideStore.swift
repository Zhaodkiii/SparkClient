import Foundation

/// 医疗文档拍摄引导页展示记录，按上下文兼容历史 UserDefaults key。
@MainActor
final class MedicalDocumentCameraGuideStore {
    static let shared = MedicalDocumentCameraGuideStore()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasSeenGuide(for context: MedicalDocumentCameraContext) -> Bool {
        userDefaults.bool(forKey: context.guideStorageKey)
    }

    func markAsSeen(for context: MedicalDocumentCameraContext) {
        userDefaults.set(true, forKey: context.guideStorageKey)
    }
}
