import SwiftUI

struct CaseHistoryDiagnosisSectionView: View {
    let draft: CaseRecognitionDraft
    let caseAttachments: [MedicalDocumentLocalAttachmentItem]
    let symptomAttachments: [MedicalDocumentLocalAttachmentItem]
    let surgeryAttachments: [MedicalDocumentLocalAttachmentItem]
    let onEditSymptom: (SymptomRecognitionDraft) -> Void
    let onEditSurgery: (SurgeryRecognitionDraft) -> Void

    private var hasContent: Bool {
        draft.symptom != nil || draft.surgery != nil || draft.diagnosis?.nilIfBlank != nil
    }

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: "病史与诊断",
            subtitle: "展示优先，编辑为辅",
            systemImage: "waveform.path.ecg.rectangle",
            badgeText: hasContent ? "已识别" : "待补充"
        ) {
                VStack(alignment: .leading, spacing: 12) {
                    MedicalDocumentResultInfoLine(title: "诊断结论", value: draft.diagnosis ?? "")
                    CaseMatchedAttachmentsGridView(title: "病历附件", attachments: caseAttachments)

                    if let symptom = draft.symptom {
                        block(title: symptom.name, detail: [
                            symptom.severity,
                            symptom.bodyPart,
                            symptom.startedAt,
                            symptom.notes
                        ], attachments: symptomAttachments) {
                            onEditSymptom(symptom)
                        }
                } else {
                    emptyHint("暂无主诉症状")
                }

                if let surgery = draft.surgery {
                    block(title: surgery.procedureName, detail: [
                        surgery.site,
                            surgery.surgeon,
                            surgery.performedAt,
                            surgery.notes
                        ], attachments: surgeryAttachments) {
                            onEditSurgery(surgery)
                        }
                }
            }
        }
    }

    private func block(
        title: String,
        detail: [String?],
        attachments: [MedicalDocumentLocalAttachmentItem],
        onEdit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑", action: onEdit)
                    .font(.subheadline.weight(.semibold))
            }

            let merged = detail.compactMap { $0?.nilIfBlank }.joined(separator: " · ")
            if merged.isEmpty == false {
                Text(merged)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            CaseMatchedAttachmentsGridView(title: "匹配附件", attachments: attachments)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
