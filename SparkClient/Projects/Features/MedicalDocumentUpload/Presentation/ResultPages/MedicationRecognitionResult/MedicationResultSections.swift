import SwiftUI

struct MedicationMemberConfirmSectionView: View {
    let memberID: Int?
    let medications: [MedicationPlanRecognitionDraft]

    var body: some View {
        MedicationResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicationResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicationResultInfoLine(
                    title: L10n.text("medical.upload.result.medication.total_count"),
                    value: "\(medications.count)"
                )
            }
        }
    }
}

struct MedicationListSectionView: View {
    let medications: [MedicationPlanRecognitionDraft]
    let onBatchEdit: () -> Void
    let onEditItem: (Int, MedicationPlanRecognitionDraft) -> Void

    var body: some View {
        MedicationResultSectionCard(
            title: L10n.text("medical.upload.result.medication.section.title"),
            subtitle: L10n.text("medical.upload.result.medication.section.subtitle"),
            systemImage: "pills",
            badgeText: String(
                format: L10n.text("medical.upload.result.medication.count_format"),
                locale: .current,
                medications.count
            ),
            actionTitle: L10n.text("medical.upload.result.medication.batch_edit"),
            action: onBatchEdit
        ) {
            if medications.isEmpty {
                Text(L10n.text("medical.upload.result.medication.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(medications.enumerated()), id: \.offset) { pair in
                        row(index: pair.offset, item: pair.element)
                    }
                }
            }
        }
    }

    private func row(index: Int, item: MedicationPlanRecognitionDraft) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .systemIndigo))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.medicineName ?? item.medicineBox?.medicineName ?? item.brandName ?? L10n.text("medical.upload.result.medication.unnamed"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let detail = [item.medicineType, item.strength, item.frequencyText, item.instructions]
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
                onEditItem(index, item)
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

struct MedicationAttachmentsSectionView: View {
    let attachments: [MedicationResultLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    var body: some View {
        MedicationResultSectionCard(
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
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .unifiedFilePreview(selection: $selectedPreview)
    }

    private func row(_ item: MedicationResultLocalAttachmentItem) -> some View {
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
