import SwiftUI


enum MedicationResultLocalEditor: Identifiable {
    case batch(PrescriptionRecognitionDraft)
    case item(index: Int, draft: MedicationPlanRecognitionDraft)

    var id: String {
        switch self {
        case .batch:
            return "batch"
        case .item(let index, _):
            return "item-\(index)"
        }
    }
}
