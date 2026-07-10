import Foundation

/// 处方/服药计划拍摄引导页展示记录。
@MainActor
final class PrescriptionMedicationCameraGuideStore {
    static let shared = PrescriptionMedicationCameraGuideStore()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasSeenGuide(for context: PrescriptionMedicationCameraContext) -> Bool {
        userDefaults.bool(forKey: storageKey(for: context))
    }

    func markAsSeen(for context: PrescriptionMedicationCameraContext) {
        userDefaults.set(true, forKey: storageKey(for: context))
    }

    private func storageKey(for context: PrescriptionMedicationCameraContext) -> String {
        switch context {
        case .prescription:
            return "spark.prescription.camera.guide.has_seen"
        case .medicationPlan:
            return "spark.medication_plan.camera.guide.has_seen"
        }
    }
}
