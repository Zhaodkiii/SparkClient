import SwiftUI


enum PrescriptionResultLocalEditor: Identifiable {
    case batch(PrescriptionRecognitionDraft)
    case medication(index: Int, draft: MedicationPlanRecognitionDraft)

    var id: String {
        switch self {
        case .batch:
            return "batch"
        case .medication(let index, _):
            return "medication-\(index)"
        }
    }
}
