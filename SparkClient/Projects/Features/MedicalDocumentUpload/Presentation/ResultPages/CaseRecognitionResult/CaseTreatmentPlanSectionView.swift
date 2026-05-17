import SwiftUI

struct CaseTreatmentPlanSectionView: View {
    let batches: [PrescriptionRecognitionDraft]
    let followUps: [FollowUpRecognitionDraft]
    let attachmentsForIDs: ([UUID]) -> [CaseLocalAttachmentItem]
    let onEditBatch: (PrescriptionRecognitionDraft) -> Void
    let onEditMedicationItem: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    let onEditFollowUp: (FollowUpRecognitionDraft) -> Void

    var body: some View {
        CaseSectionCard(
            title: "治疗方案",
            subtitle: "处方批次 + 随访计划",
            systemImage: "pills",
            badgeText: "\(batches.count + followUps.count)组"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if batches.isEmpty {
                    emptyHint("暂无处方批次")
                } else {
                    ForEach(Array(batches.enumerated()), id: \.offset) { pair in
                        batchCard(index: pair.offset, batch: pair.element)
                    }
                }

                Divider()

                if followUps.isEmpty {
                    emptyHint("暂无随访计划")
                } else {
                    ForEach(Array(followUps.enumerated()), id: \.offset) { _, item in
                        followUpCard(item)
                    }
                }
            }
        }
    }

    private func batchCard(index: Int, batch: PrescriptionRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(batch.institutionName ?? "处方批次")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑批次") {
                    onEditBatch(batch)
                }
                .font(.subheadline.weight(.semibold))
            }

            let head = [batch.prescriberName, batch.prescribedAt, batch.diagnosis]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            if head.isEmpty == false {
                Text(head)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let meds = batch.medicationPlans ?? []
            if meds.isEmpty {
                Text("暂无药品")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meds.enumerated()), id: \.offset) { medPair in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "capsule")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .systemIndigo))
                            Text(medPair.element.medicineName ?? medPair.element.medicineBox?.medicineName ?? medPair.element.brandName ?? "未命名药品")
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button("编辑") {
                                onEditMedicationItem(index, medPair.offset, medPair.element)
                            }
                            .font(.caption.weight(.semibold))
                        }

                        CaseMatchedAttachmentsGridView(
                            title: "药品附件",
                            attachments: attachmentsForIDs(medPair.element.attachmentFileIds)
                        )
                    }
                }
            }

            CaseMatchedAttachmentsGridView(title: "处方附件", attachments: attachmentsForIDs(batch.attachmentFileIds))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func followUpCard(_ item: FollowUpRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(item.method ?? "随访")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑") {
                    onEditFollowUp(item)
                }
                .font(.subheadline.weight(.semibold))
            }

            let detail = [item.status, item.plannedAt, item.completedAt, item.nextAction]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            Text(detail.isEmpty ? "-" : detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            CaseMatchedAttachmentsGridView(title: "匹配附件", attachments: attachmentsForIDs(item.attachmentFileIds))
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
