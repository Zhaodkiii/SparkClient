import SwiftUI

// MARK: - 服药计划成员确认信息区块视图
/// 服药计划识别结果页：展示就诊人、成员切换与药品数量概览
struct MedicationMemberConfirmSectionView: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    let medicationCount: Int
    var onSelectMember: ((Int?) -> Void)?

    private var selectedMemberName: String {
        guard let selectedMemberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return memberContextStore.context.members.first(where: { $0.id == selectedMemberID })?.name
            ?? "\(selectedMemberID)"
    }

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.medication.member.subtitle", fallback: "确认保存到该成员的服药计划"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                memberRow
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.medication.total_count"),
                    value: "\(medicationCount)"
                )
            }
        }
    }

    @ViewBuilder
    private var memberRow: some View {
        if let onSelectMember {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("medical.upload.result.member.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MemberProfileBindingMenu(
                    memberContextStore: memberContextStore,
                    selectedMemberID: selectedMemberID,
                    onSelect: onSelectMember
                ) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.accentColor)
                        Text(selectedMemberName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }
        } else {
            MedicalDocumentResultInfoLine(
                title: L10n.text("medical.upload.result.member.id"),
                value: selectedMemberName
            )
        }
    }
}

// MARK: - 服药计划列表区块视图
/// 服药计划识别结果页：区块头部展示摘要，每条计划独立卡片展示在内容区
struct MedicationListSectionView: View {
    let medications: [MedicationPlanRecognitionDraft]
    var validationIssues: [MedicalPreSubmitValidationIssue] = []
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    var detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    let onUpdateMedicationDraft: (Int, MedicationPlanRecognitionDraft) -> Void
    let onDeleteMedicationDraft: (Int) -> Void
    let onManageAttachments: (Int) -> Void

    private var badgeText: String {
        String(
            format: L10n.text("medical.upload.result.medication.count_format"),
            locale: .current,
            medications.count
        )
    }

    var body: some View {
        Section {
            if medications.isEmpty {
                emptyHint(L10n.text("medical.upload.result.medication.empty"))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(medications.enumerated()), id: \.offset) { pair in
                        medicationCard(index: pair.offset, item: pair.element)
                    }
                }
            }
        } header: {
            sectionHeader
                .contentShape(Rectangle())
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pills.fill")
                .font(.title3)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("medical.upload.result.medication.section.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(L10n.text("medical.upload.result.medication.section.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
    }

    @ViewBuilder
    private func medicationCard(index: Int, item: MedicationPlanRecognitionDraft) -> some View {
        if let detailNavigationContext {
            MainNavigationLink {
                medicationDetailDestination(index: index, draft: item, context: detailNavigationContext)
            } label: {
                medicationCardContent(index: index, item: item)
            }
            .buttonStyle(.plain)
        } else {
            medicationCardContent(index: index, item: item)
        }
    }

    private func medicationCardContent(index: Int, item: MedicationPlanRecognitionDraft) -> some View {
        let pathPrefix = "medication_plans[\(index)]"
        let itemIssues = validationIssues.issues(matchingFieldPathPrefix: pathPrefix)
        let hasError = itemIssues.isEmpty == false
        let scrollTargetID = itemIssues.first?.scrollTargetID
            ?? MedicalPreSubmitValidationIssue.makeScrollTargetID(
                resourceType: .medicationPlan,
                fieldKey: "medication_plans[\(index)].drug_name",
                cardIndex: index,
                prescriptionIndex: nil
            )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemIndigo))

                VStack(alignment: .leading, spacing: 4) {
                    if medications.count > 1 {
                        Text("\(index + 1) / \(medications.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(item.medicineName ?? item.medicineBox?.medicineName ?? item.brandName ?? L10n.text("medical.upload.result.medication.unnamed"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(hasError ? .red : .primary)
                            .lineLimit(1)

                        let detail = [item.strength, item.dosePerTime]
                            .compactMap { $0?.nilIfBlank }
                            .joined(separator: " · ")
                        if detail.isEmpty == false {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    let frequencyText = [item.frequencyText, medicationReminderTimesDisplay(item.reminderTimes)]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " · ")
                    if frequencyText.isEmpty == false {
                        Text(frequencyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let instructions = item.instructions?.nilIfBlank {
                        HStack {
                            Text(L10n.text("medication_plan.form.field.instructions"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if hasError {
                    MedicalValidationIssueBadge()
                }
                if detailNavigationContext != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.gray)
                }
            }
            .contentShape(Rectangle())

            ForEach(itemIssues.prefix(2)) { issue in
                MedicalValidationIssueInlineView(message: issue.message)
            }

            if let attachmentsForIDs, item.attachmentFileIds.isEmpty == false {
                CaseMatchedAttachmentsGridView(
                    title: "用药附件",
                    attachments: attachmentsForIDs(item.attachmentFileIds),
                    onManage: {
                        onManageAttachments(index)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
        .medicalValidationCardChrome(
            hasError: hasError,
            scrollTargetID: scrollTargetID
        )
    }

    private func medicationDetailDestination(
        index: Int,
        draft: MedicationPlanRecognitionDraft,
        context: MedicalDocumentResultDetailNavigationContext
    ) -> some View {
        let explicitlyUnlinked = PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(draft)
        let boxID = explicitlyUnlinked
            ? nil
            : PrescriptionRecognitionDraftMapper.temporaryStandaloneMedicineBoxID(index: index)
        let plan = draft.remoteMedicationPlan(
            memberID: context.memberID,
            id: PrescriptionRecognitionDraftMapper.temporaryStandalonePlanID(index: index),
            prescriptionID: nil,
            medicineBoxID: boxID,
            medicalCaseID: nil
        )
        let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
        if let boxID, !explicitlyUnlinked {
            medicineBoxes = [draft.remoteMedicineBox(memberID: context.memberID, id: boxID)]
        } else {
            medicineBoxes = []
        }

        return MedicationPlanDetailPage(
            mode: .localDraft,
            plan: plan,
            medicineBoxes: medicineBoxes,
            memberID: context.memberID,
            completeData: nil,
            memberContextStore: context.memberContextStore,
            workflowAPI: context.workflowAPI,
            fileTransferService: context.fileTransferService,
            notificationClient: context.notificationClient,
            sourcePlanDraft: draft,
            onSaved: { _ in },
            onDeleted: { _ in },
            onMedicineBoxSaved: { _ in },
            onLocalDraftSaved: { updated in
                onUpdateMedicationDraft(index, updated)
            },
            onLocalDraftDeleted: {
                onDeleteMedicationDraft(index)
            },
            onLocalDraftMedicineBoxSaved: { _ in },
            onLocalDraftMedicineBoxDeleted: {}
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

private func medicationReminderTimesDisplay(_ times: [ReminderTime]?) -> String? {
    guard let times, times.isEmpty == false else { return nil }
    let formatted = times.map { entry -> String in
        if let doseText = entry.doseText?.nilIfBlank {
            return "\(entry.time) \(doseText)"
        }
        if let dose = entry.dose {
            let doseString = dose.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", dose)
                : String(dose)
            return "\(entry.time) \(doseString)"
        }
        return entry.time
    }
    let summary = formatted.joined(separator: "、")
    return summary.isEmpty ? nil : summary
}
