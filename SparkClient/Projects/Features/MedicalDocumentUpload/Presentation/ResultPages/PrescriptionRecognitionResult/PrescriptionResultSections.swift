import SwiftUI

struct PrescriptionMemberConfirmSectionView: View {
    let memberID: Int?
    let batch: PrescriptionRecognitionDraft

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.batch_no"),
                    value: batch.prescriptionNo ?? ""
                )
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.hospital"),
                    value: batch.institutionName ?? ""
                )
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.prescriber"),
                    value: batch.prescriberName ?? ""
                )
            }
        }
    }
}

struct PrescriptionBatchListSectionView: View {
    let batches: [PrescriptionRecognitionDraft]
    var followUps: [FollowUpRecognitionDraft] = []
    var title: String = L10n.text("medical.upload.result.prescription.batch_section.title")
    var subtitle: String = L10n.text("medical.upload.result.prescription.batch_section.subtitle")
    var badgeText: String?
    var tintColor: Color = Color(uiColor: .systemBlue)
    var actionTitle: String? = L10n.text("medical.upload.result.prescription.edit_batch")
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    let onEditBatch: (Int, PrescriptionRecognitionDraft) -> Void
    let onEditMedication: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    var onEditFollowUp: ((FollowUpRecognitionDraft) -> Void)?
    var onManageBatchAttachments: ((Int, PrescriptionRecognitionDraft) -> Void)?
    var onManageMedicationAttachments: ((Int, Int, MedicationPlanRecognitionDraft) -> Void)?
    var onManageFollowUpAttachments: ((Int, FollowUpRecognitionDraft) -> Void)?

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: title,
            subtitle: subtitle,
            systemImage: "pills",
            tintColor: tintColor,
            badgeText: badgeText ?? defaultBadgeText,
            actionTitle: firstBatch == nil ? nil : actionTitle,
            action: { firstBatch.map { onEditBatch(0, $0) } }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if batches.isEmpty {
                    emptyHint(L10n.text("medical.upload.result.prescription.empty_medications"))
                } else {
                    ForEach(Array(batches.enumerated()), id: \.offset) { pair in
                        batchCard(index: pair.offset, batch: pair.element)
                    }
                }

                if followUps.isEmpty == false {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption)
                                .foregroundStyle(tintColor)
                            Text("随访计划")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(followUps.count)组")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                )
                        }

                        ForEach(Array(followUps.enumerated()), id: \.offset) { pair in
                            followUpCard(index: pair.offset, item: pair.element)
                        }
                    }
                }
            }
        }
    }

    private var firstBatch: PrescriptionRecognitionDraft? {
        batches.first
    }

    private var medicationCount: Int {
        batches.reduce(0) { $0 + ($1.medicationPlans?.count ?? 0) }
    }

    private var defaultBadgeText: String {
        String(
            format: L10n.text("medical.upload.result.prescription.medication_count"),
            locale: .current,
            medicationCount
        )
    }

    private func batchCard(index: Int, batch: PrescriptionRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(batch.institutionName ?? "处方批次")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(L10n.text("medical.upload.result.prescription.edit_batch")) {
                    onEditBatch(index, batch)
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
                Text(L10n.text("medical.upload.result.prescription.empty_medications"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meds.enumerated()), id: \.offset) { pair in
                    medicationRow(batchIndex: index, itemIndex: pair.offset, draft: pair.element)
                }
            }

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "处方附件",
                    attachments: attachmentsForIDs(batch.attachmentFileIds),
                    onManage: {
                        onManageBatchAttachments?(index, batch)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func medicationRow(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemIndigo))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.medicineName ?? draft.medicineBox?.medicineName ?? draft.brandName ?? L10n.text("medical.upload.result.medication.unnamed"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    let detail = [draft.strength, draft.frequencyText, draft.instructions]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " · ")
                    if detail.isEmpty == false {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(L10n.text("common.edit")) {
                    onEditMedication(batchIndex, itemIndex, draft)
                }
                .font(.caption.weight(.semibold))
            }

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "药品附件",
                    attachments: attachmentsForIDs(draft.attachmentFileIds),
                    onManage: {
                        onManageMedicationAttachments?(batchIndex, itemIndex, draft)
                    }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func followUpCard(index: Int, item: FollowUpRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(item.method ?? "随访")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let onEditFollowUp {
                    Button("编辑") {
                        onEditFollowUp(item)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            let detail = [item.status, item.plannedAt, item.completedAt, item.nextAction]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            Text(detail.isEmpty ? "-" : detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "匹配附件",
                    attachments: attachmentsForIDs(item.attachmentFileIds),
                    onManage: {
                        onManageFollowUpAttachments?(index, item)
                    }
                )
            }
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
