import SwiftUI

struct CaseVisitInfoSectionView: View {
    let visit: VisitRecognitionDraft?
    let attachments: [MedicalDocumentLocalAttachmentItem]
    let onEdit: (VisitRecognitionDraft) -> Void

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: "就诊信息",
            subtitle: "时间、科室、医师等基础要素",
            systemImage: "stethoscope",
            actionTitle: visit == nil ? nil : "编辑",
            action: {
                if let visit {
                    onEdit(visit)
                }
            }
        ) {
            if let visit {
                VStack(alignment: .leading, spacing: 10) {
                    MedicalDocumentResultInfoLine(title: "就诊类型", value: visit.visitType ?? "")
                    MedicalDocumentResultInfoLine(title: "就诊时间", value: visit.visitedAt ?? "")
                    MedicalDocumentResultInfoLine(title: "科室", value: visit.department ?? "")
                    MedicalDocumentResultInfoLine(title: "医生", value: visit.doctorName ?? "")
                    MedicalDocumentResultInfoLine(title: "备注", value: visit.notes ?? "")
                    CaseMatchedAttachmentsGridView(title: "匹配附件", attachments: attachments)
                }
            } else {
                Text("暂无就诊信息")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
