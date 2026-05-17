import SwiftUI


enum MedicalReportResultLocalEditor: Identifiable {
    case report(index: Int, draft: MedicalReportRecognitionDraft)

    var id: String {
        switch self {
        case .report(let index, _):
            return "report-\(index)"
        }
    }
}
