import SwiftUI

enum PrescriptionResultLocalEditor: Identifiable {
    case batch(index: Int, batch: PrescriptionRecognitionDraft)
    case medication(batchIndex: Int, index: Int, draft: MedicationPlanRecognitionDraft)
    case medicineCandidate(batchIndex: Int, index: Int, draft: MedicationPlanRecognitionDraft)

    var id: String {
        switch self {
        case .batch(let index, _):
            return "batch-\(index)"
        case .medication(let batchIndex, let index, _):
            return "medication-\(batchIndex)-\(index)"
        case .medicineCandidate(let batchIndex, let index, _):
            return "medicine-candidate-\(batchIndex)-\(index)"
        }
    }
}

enum PrescriptionAttachmentTarget: Identifiable {
    case batch(index: Int)
    case medication(batchIndex: Int, index: Int)
    case medicineBoxCandidate(batchIndex: Int, index: Int)

    var id: String {
        switch self {
        case .batch(let index):
            return "batch-\(index)"
        case .medication(let batchIndex, let index):
            return "medication-\(batchIndex)-\(index)"
        case .medicineBoxCandidate(let batchIndex, let index):
            return "medicine-box-candidate-\(batchIndex)-\(index)"
        }
    }

    var title: String {
        switch self {
        case .batch:
            return "关联处方附件"
        case .medication:
            return "关联药品附件"
        case .medicineBoxCandidate:
            return "关联药箱附件"
        }
    }
}
