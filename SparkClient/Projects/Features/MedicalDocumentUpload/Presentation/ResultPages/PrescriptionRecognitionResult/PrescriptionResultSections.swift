import SwiftUI

struct PrescriptionMemberConfirmSectionView: View {
    let memberID: Int?
    let batch: PrescriptionRecognitionDraft

    var body: some View {
        PrescriptionResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                PrescriptionResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                PrescriptionResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.batch_no"),
                    value: batch.batchNo ?? ""
                )
                PrescriptionResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.hospital"),
                    value: batch.institutionName ?? ""
                )
                PrescriptionResultInfoLine(
                    title: L10n.text("medical.upload.result.prescription.prescriber"),
                    value: batch.prescriberName ?? ""
                )
            }
        }
    }
}

struct PrescriptionBatchListSectionView: View {
    let batch: PrescriptionRecognitionDraft
    let onEditBatch: () -> Void
    let onEditMedication: (Int, MedicationRecognitionDraft) -> Void

    var body: some View {
        let meds = batch.medications ?? []
        PrescriptionResultSectionCard(
            title: L10n.text("medical.upload.result.prescription.batch_section.title"),
            subtitle: L10n.text("medical.upload.result.prescription.batch_section.subtitle"),
            systemImage: "pills",
            badgeText: String(
                format: L10n.text("medical.upload.result.prescription.medication_count"),
                locale: .current,
                meds.count
            ),
            actionTitle: L10n.text("medical.upload.result.prescription.edit_batch"),
            action: onEditBatch
        ) {
            if meds.isEmpty {
                Text(L10n.text("medical.upload.result.prescription.empty_medications"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(meds.enumerated()), id: \.offset) { pair in
                        medicationRow(index: pair.offset, draft: pair.element)
                    }
                }
            }
        }
    }

    private func medicationRow(index: Int, draft: MedicationRecognitionDraft) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .systemIndigo))

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.drugName ?? draft.genericName ?? L10n.text("medical.upload.result.medication.unnamed"))
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

            Button(L10n.text("medical.upload.result.common.edit")) {
                onEditMedication(index, draft)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct PrescriptionAttachmentsSectionView: View {
    let attachments: [PrescriptionResultLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    var body: some View {
        PrescriptionResultSectionCard(
            title: L10n.text("medical.upload.result.attachments.title"),
            subtitle: L10n.text("medical.upload.result.attachments.subtitle"),
            systemImage: "paperclip",
            badgeText: String(
                format: L10n.text("medical.upload.result.attachments.count"),
                locale: .current,
                attachments.count
            )
        ) {
            if attachments.isEmpty {
                Text(L10n.text("medical.upload.result.attachments.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(attachments) { item in
                        Button {
                            selectedPreview = item.previewInput
                        } label: {
                            attachmentRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .unifiedFilePreview(selection: $selectedPreview)
    }

    private func attachmentRow(_ item: PrescriptionResultLocalAttachmentItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 40, height: 40)
                Image(systemName: item.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
