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
