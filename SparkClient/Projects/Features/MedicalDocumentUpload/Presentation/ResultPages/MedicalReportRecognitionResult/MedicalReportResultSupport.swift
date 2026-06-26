import SwiftUI

struct MedicalReportAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medical-report-\(index)" }
    var title: String { "关联检查报告附件" }
}
