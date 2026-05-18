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

enum PrescriptionAttachmentTarget: Identifiable {
    case batch
    case medication(index: Int)

    var id: String {
        switch self {
        case .batch:
            return "batch"
        case .medication(let index):
            return "medication-\(index)"
        }
    }

    var title: String {
        switch self {
        case .batch:
            return "关联处方附件"
        case .medication:
            return "关联药品附件"
        }
    }
}
