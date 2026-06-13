import SwiftUI

enum PrescriptionResultLocalEditor: Identifiable {
    case batch(index: Int, batch: PrescriptionRecognitionDraft)
    case medication(batchIndex: Int, index: Int, draft: MedicationPlanRecognitionDraft)

    var id: String {
        switch self {
        case .batch(let index, _):
            return "batch-\(index)"
        case .medication(let batchIndex, let index, _):
            return "medication-\(batchIndex)-\(index)"
        }
    }
}

enum PrescriptionAttachmentTarget: Identifiable {
    case batch(index: Int)
    case medication(batchIndex: Int, index: Int)

    var id: String {
        switch self {
        case .batch(let index):
            return "batch-\(index)"
        case .medication(let batchIndex, let index):
            return "medication-\(batchIndex)-\(index)"
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
