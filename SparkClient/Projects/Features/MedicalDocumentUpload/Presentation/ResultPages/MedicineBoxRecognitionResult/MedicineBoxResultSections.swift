import SwiftUI

// MARK: - 药箱成员确认信息区块视图
/// 药箱识别结果页：展示就诊人、成员切换与药品数量概览
struct MedicineBoxMemberConfirmSectionView: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    let medicineCount: Int
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
            title: L10n.text("medical.upload.result.medicine_box.member.title", fallback: "确认成员"),
            subtitle: L10n.text("medical.upload.result.medicine_box.member.subtitle", fallback: "保存后会加入该成员的药箱"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                memberRow
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.medicine_box.total_count", fallback: "药品数量"),
                    value: "\(medicineCount)"
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

// MARK: - 药箱药品列表区块视图
/// 药箱识别结果页：区块头部展示药箱摘要，每条药品独立卡片展示在内容区
struct MedicineBoxListSectionView: View {
    let items: [MedicineBoxRecognitionDraft]
    var validationIssues: [MedicalPreSubmitValidationIssue] = []
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    var detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    let onLocalDraftSaved: (Int, MedicineBoxRecognitionDraft) -> Void
    let onLocalDraftDeleted: (Int) -> Void
    let onEdit: (Int, MedicineBoxRecognitionDraft) -> Void
    let onManageAttachments: (Int) -> Void

    private var badgeText: String {
        String(
            format: L10n.text("medical.upload.result.medication.count_format"),
            locale: .current,
            items.count
        )
    }

    var body: some View {
        Section {
            if items.isEmpty {
                emptyHint(L10n.text("medical.upload.result.medicine_box.empty", fallback: "暂无药品"))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { pair in
                        itemCard(index: pair.offset, item: pair.element)
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
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("medical.upload.result.medicine_box.section.title", fallback: "药箱药品"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(L10n.text("medical.upload.result.medicine_box.section.subtitle", fallback: "可逐条编辑识别结果后保存"))
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
    private func itemCard(index: Int, item: MedicineBoxRecognitionDraft) -> some View {
        if let detailNavigationContext {
            MainNavigationLink {
                medicineBoxDetailDestination(index: index, item: item, context: detailNavigationContext)
            } label: {
                itemCardContent(index: index, item: item)
            }
            .buttonStyle(.plain)
        } else {
            itemCardContent(index: index, item: item)
        }
    }

    private func itemCardContent(index: Int, item: MedicineBoxRecognitionDraft) -> some View {
        let cardIssues = validationIssues.issues(forCardIndex: index, resourceType: .medicineBox)
        let hasError = cardIssues.isEmpty == false
        let previewBox = detailNavigationContext.map {
            item.remoteMedicineBox(
                memberID: $0.memberID,
                id: PrescriptionRecognitionDraftMapper.temporaryMedicineBoxRecognitionID(index: index)
            )
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemIndigo))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    if items.count > 1 {
                        Text("\(index + 1) / \(items.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(item.medicineName?.nilIfBlank ?? L10n.text("medical.upload.presubmit.value.not_filled"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(hasError ? .red : .primary)
                        .lineLimit(2)

                    infoLine(
                        title: L10n.text("home.medical.medicine_box.field.medicine_type"),
                        value: medicineTypeText(item.medicineType)
                    )
                    infoLine(
                        title: L10n.text("medical_record.forms.field.brand_name"),
                        value: item.brandName
                    )
                    infoLine(
                        title: L10n.text("medical_record.forms.field.dosage_form"),
                        value: item.dosageForm
                    )
                    infoLine(
                        title: L10n.text("medical_record.forms.field.strength"),
                        value: medicineStrengthText(item.strength)
                    )
                    infoLine(
                        title: L10n.text("home.medical.medicine_box.field.total_quantity"),
                        value: previewBox.map(medicineBoxStockText)
                            ?? item.totalQuantity?.nilIfBlank
                    )
                    infoLine(
                        title: L10n.text("home.medical.medicine_box.field.expire_date"),
                        value: item.expireDate?.nilIfBlank
                    )
                    infoLine(
                        title: L10n.text("medical_record.forms.field.notes"),
                        value: item.notes
                    )
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if hasError {
                        MedicalValidationIssueBadge()
                    }
                    Button(L10n.text("common.edit")) {
                        onEdit(index, item)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    if detailNavigationContext != nil {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.gray)
                    }
                }
            }
            .contentShape(Rectangle())

            ForEach(cardIssues.prefix(2)) { issue in
                MedicalValidationIssueInlineView(message: issue.message)
            }

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "药品附件",
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
            scrollTargetID: "preSubmitValidation.card.medicineBox.\(index)"
        )
    }

    @ViewBuilder
    private func infoLine(title: String, value: String?) -> some View {
        if let value = value?.nilIfBlank {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func medicineBoxDetailDestination(
        index: Int,
        item: MedicineBoxRecognitionDraft,
        context: MedicalDocumentResultDetailNavigationContext
    ) -> some View {
        let box = item.remoteMedicineBox(
            memberID: context.memberID,
            id: PrescriptionRecognitionDraftMapper.temporaryMedicineBoxRecognitionID(index: index)
        )

        MedicineBoxDetailPage(
            mode: .localDraft,
            box: box,
            entryMemberID: context.memberID,
            memberOptions: context.memberContextStore.context.members,
            allowsHouseholdPublic: false,
            typeOptions: MedicineBoxTypeCatalog.defaultStoredOptions,
            specOptionBoxes: [],
            workflowAPI: context.workflowAPI,
            fileTransferService: context.fileTransferService,
            sourceBoxDraft: item,
            onSaved: { _ in },
            onDeleted: { _ in },
            onLocalDraftSaved: { updated in
                onLocalDraftSaved(index, updated)
            },
            onLocalDraftDeleted: {
                onLocalDraftDeleted(index)
            }
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
