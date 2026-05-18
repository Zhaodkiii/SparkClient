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

struct MedicalReportAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medical-report-\(index)" }
    var title: String { "关联检查报告附件" }
}
