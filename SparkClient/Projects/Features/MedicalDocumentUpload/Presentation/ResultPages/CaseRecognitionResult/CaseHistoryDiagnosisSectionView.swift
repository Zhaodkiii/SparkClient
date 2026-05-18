import SwiftUI

struct CaseHistoryDiagnosisSectionView: View {
    let draft: CaseRecognitionDraft
    let caseAttachments: [MedicalDocumentLocalAttachmentItem]
    let symptomAttachments: [MedicalDocumentLocalAttachmentItem]
    let visitAttachments: [MedicalDocumentLocalAttachmentItem]
    let surgeryAttachments: [MedicalDocumentLocalAttachmentItem]
    let onEditCase: () -> Void
    let onEditSymptom: (SymptomRecognitionDraft) -> Void
    let onEditVisit: (VisitRecognitionDraft) -> Void
    let onEditSurgery: (SurgeryRecognitionDraft) -> Void
    var onManageCaseAttachments: (() -> Void)?
    var onManageSymptomAttachments: (() -> Void)?
    var onManageVisitAttachments: (() -> Void)?
    var onManageSurgeryAttachments: (() -> Void)?

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: "病史、诊断与就诊",
            subtitle: "诊断结论、症状、就诊与手术信息",
            systemImage: "waveform.path.ecg.rectangle",
            actionTitle: "编辑",
            action: onEditCase,
            enableCollapse: true,
            defaultCollapsed: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MedicalDocumentResultInfoLine(title: "诊断结论", value: draft.diagnosis ?? "")
                CaseMatchedAttachmentsGridView(
                    title: "病历附件",
                    attachments: caseAttachments,
                    onManage: onManageCaseAttachments
                )

                if let symptom = draft.symptom {
                    block(
                        title: symptom.name,
                        detail: [
                            symptom.severity,
                            symptom.bodyPart,
                            symptom.startedAt,
                            symptom.notes
                        ],
                        attachments: symptomAttachments,
                        onManageAttachments: onManageSymptomAttachments
                    ) {
                        onEditSymptom(symptom)
                    }
                } else {
                    emptyHint("暂无主诉症状")
                }

                if let visit = draft.visit {
                    visitBlock(visit, attachments: visitAttachments) {
                        onEditVisit(visit)
                    }
                } else {
                    emptyHint("暂无就诊信息")
                }

                if let surgery = draft.surgery {
                    block(
                        title: surgery.procedureName,
                        detail: [
                            surgery.site,
                            surgery.surgeon,
                            surgery.performedAt,
                            surgery.notes
                        ],
                        attachments: surgeryAttachments,
                        onManageAttachments: onManageSurgeryAttachments
                    ) {
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
        onManageAttachments: (() -> Void)?,
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

            CaseMatchedAttachmentsGridView(
                title: "匹配附件",
                attachments: attachments,
                onManage: onManageAttachments
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func visitBlock(
        _ visit: VisitRecognitionDraft,
        attachments: [MedicalDocumentLocalAttachmentItem],
        onEdit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("就诊信息", systemImage: "stethoscope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑", action: onEdit)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(title: "就诊类型", value: visit.visitType ?? "")
                MedicalDocumentResultInfoLine(title: "就诊时间", value: visit.visitedAt ?? "")
                MedicalDocumentResultInfoLine(title: "科室", value: visit.department ?? "")
                MedicalDocumentResultInfoLine(title: "医生", value: visit.doctorName ?? "")
                MedicalDocumentResultInfoLine(title: "备注", value: visit.notes ?? "")
            }

            CaseMatchedAttachmentsGridView(
                title: "匹配附件",
                attachments: attachments,
                onManage: onManageVisitAttachments
            )
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
