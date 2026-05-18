import SwiftUI


enum CaseRecognitionLocalEditor: Identifiable {
    case visit(VisitRecognitionDraft)
    case symptom(SymptomRecognitionDraft)
    case surgery(SurgeryRecognitionDraft)
    case medicationBatch(PrescriptionRecognitionDraft)
    case medicationItem(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft)
    case followUp(FollowUpRecognitionDraft)
    case exam(index: Int, draft: MedicalReportRecognitionDraft)

    var id: String {
        switch self {
        case .visit:
            return "visit"
        case .symptom:
            return "symptom"
        case .surgery:
            return "surgery"
        case .medicationBatch:
            return "medicationBatch"
        case .medicationItem(let batchIndex, let itemIndex, _):
            return "medicationItem-\(batchIndex)-\(itemIndex)"
        case .followUp:
            return "followUp"
        case .exam(let index, _):
            return "exam-\(index)"
        }
    }
}

enum CaseRecognitionAttachmentTarget: Identifiable {
    case caseDraft
    case symptom
    case surgery
    case visit
    case exam(index: Int)
    case prescription(index: Int)
    case medication(batchIndex: Int, itemIndex: Int)
    case followUp(index: Int)

    var id: String {
        switch self {
        case .caseDraft:
            return "case"
        case .symptom:
            return "symptom"
        case .surgery:
            return "surgery"
        case .visit:
            return "visit"
        case .exam(let index):
            return "exam-\(index)"
        case .prescription(let index):
            return "prescription-\(index)"
        case .medication(let batchIndex, let itemIndex):
            return "medication-\(batchIndex)-\(itemIndex)"
        case .followUp(let index):
            return "followUp-\(index)"
        }
    }

    var title: String {
        switch self {
        case .caseDraft:
            return "关联病历附件"
        case .symptom:
            return "关联症状附件"
        case .surgery:
            return "关联手术附件"
        case .visit:
            return "关联就诊附件"
        case .exam:
            return "关联检查报告附件"
        case .prescription:
            return "关联处方附件"
        case .medication:
            return "关联药品附件"
        case .followUp:
            return "关联随访附件"
        }
    }
}

extension CaseRecognitionDraft {
    var infoDensityCount: Int {
        [summary, diagnosis, hospitalName, ageAtVisit, occurredAt]
            .compactMap { $0?.nilIfBlank }
            .count
            + (symptom == nil ? 0 : 1)
            + (visit == nil ? 0 : 1)
            + (surgery == nil ? 0 : 1)
            + ((followUps?.isEmpty == false) ? 1 : 0)
            + ((prescriptions?.isEmpty == false) ? 1 : 0)
            + ((examinationReports?.isEmpty == false) ? 1 : 0)
    }
}
