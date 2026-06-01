import SwiftUI

struct MedicationMemberConfirmSectionView: View {
    let memberID: Int?
    let medications: [MedicationPlanRecognitionDraft]

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark",
            tintColor: Color(uiColor: .systemTeal)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.medication.total_count"),
                    value: "\(medications.count)"
                )
            }
        }
    }
}

struct MedicationListSectionView: View {
    let medications: [MedicationPlanRecognitionDraft]
    var validationIssues: [MedicalPreSubmitValidationIssue] = []
    var expandedSectionIDs: Binding<Set<String>>?
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    let onBatchEdit: () -> Void
    let onEditItem: (Int, MedicationPlanRecognitionDraft) -> Void
    var onManageAttachments: ((Int, MedicationPlanRecognitionDraft) -> Void)?

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.medication.section.title"),
            subtitle: L10n.text("medical.upload.result.medication.section.subtitle"),
            systemImage: "pills",
            tintColor: Color(uiColor: .systemTeal),
            badgeText: String(
                format: L10n.text("medical.upload.result.medication.count_format"),
                locale: .current,
                medications.count
            ),
            actionTitle: L10n.text("medical.upload.result.medication.batch_edit"),
            action: onBatchEdit,
            enableCollapse: true,
            defaultCollapsed: true,
            collapseSectionID: MedicalPreSubmitValidationSectionID.medicationList,
            expandedSectionIDs: expandedSectionIDs
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
        let pathPrefix = "medication_plans[\(index)]"
        let itemIssues = validationIssues.issues(matchingFieldPathPrefix: pathPrefix)
        let hasError = itemIssues.isEmpty == false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemIndigo))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.medicineName ?? item.medicineBox?.medicineName ?? item.brandName ?? L10n.text("medical.upload.result.medication.unnamed"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(hasError ? .red : .primary)
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

                if hasError {
                    MedicalValidationIssueBadge()
                }

                Button(L10n.text("common.edit")) {
                    onEditItem(index, item)
                }
                .font(.caption.weight(.semibold))
            }

            ForEach(itemIssues.prefix(2)) { issue in
                MedicalValidationIssueInlineView(message: issue.message)
            }

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "药品附件",
                    attachments: attachmentsForIDs(item.attachmentFileIds),
                    onManage: {
                        onManageAttachments?(index, item)
                    }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .medicalValidationCardChrome(
            hasError: hasError,
            scrollTargetID: itemIssues.first?.scrollTargetID
                ?? MedicalPreSubmitValidationIssue.makeScrollTargetID(
                    resourceType: .medicationPlan,
                    fieldKey: "medication_plans[\(index)].drug_name",
                    cardIndex: index,
                    prescriptionIndex: nil
                )
        )
    }
}
