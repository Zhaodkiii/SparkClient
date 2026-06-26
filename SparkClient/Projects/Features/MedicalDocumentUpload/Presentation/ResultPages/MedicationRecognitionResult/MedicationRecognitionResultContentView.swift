import SwiftUI

/// 用药方案 / 服药计划 识别结果页面
/// 功能：展示AI识别的【用药计划】（药品 + 用法用量 + 服用时长）→ 支持编辑 → 保存
struct MedicationRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 当前选中的家庭成员 ID，用于保存归属
    @State private var selectedMemberID: Int?
    /// 用药方案列表（核心：药品 + 怎么吃 + 吃多久）
    @State private var medicationPlans: [MedicationPlanRecognitionDraft]
    @State private var attachmentTarget: MedicationAttachmentTarget?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?
    /// 日志工具
    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    /// 初始化：从 AI 输出中提取【用药计划】数据
    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output
        _selectedMemberID = State(initialValue: output.envelope.memberID)

        if case .medicationPlan(let meds) = output.typedResult {
            _medicationPlans = State(initialValue: meds)
        } else {
            _medicationPlans = State(initialValue: [])
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }
    private var validationIssues: [MedicalPreSubmitValidationIssue] { viewModel.preSubmitValidationIssues }
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: selectedMemberID,
            viewModel: viewModel,
            logger: logger
        )
    }

    /// 附件（上传的用药单照片）
    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(medicationPlans.associatedAttachmentFileIDs)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedicalPreSubmitValidationSummaryBanner(issues: validationIssues) { issue in
                        MedicalPreSubmitValidationNavigation.reveal(
                            issue: issue,
                            expandedSectionIDs: $expandedValidationSections,
                            scrollProxy: scrollProxy
                        )
                    }

                    MedicationMemberConfirmSectionView(
                        memberContextStore: viewModel.memberContextStoreForLocalForms,
                        selectedMemberID: selectedMemberID,
                        medicationCount: medicationPlans.count,
                        onSelectMember: { memberID in
                            selectedMemberID = memberID
                            viewModel.updateResultMemberID(memberID)
                        }
                    )

                    MedicationListSectionView(
                        medications: medicationPlans,
                        validationIssues: validationIssues,
                        attachmentsForIDs: matchedAttachments(for:),
                        detailNavigationContext: detailNavigationContext,
                        onUpdateMedicationDraft: updateMedicationDraft(at:draft:),
                        onDeleteMedicationDraft: deleteMedicationDraft(at:),
                        onManageAttachments: { index in
                            attachmentTarget = MedicationAttachmentTarget(index: index)
                        }
                    )

                    MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                    if let saveReceipt {
                        MedicalDocumentResultSectionCard(
                            title: L10n.text("medical.upload.result.common.save_status"),
                            subtitle: L10n.text("medical.upload.result.common.save_success"),
                            systemImage: "checkmark.circle",
                            badgeText: L10n.text("medical.upload.result.common.saved")
                        ) {
                            MedicalDocumentResultInfoLine(
                                title: L10n.text("medical.upload.result.common.record_id"),
                                value: "\(saveReceipt.recordID)"
                            )
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: validationIssues.map(\.id)) { _ in
                MedicalPreSubmitValidationNavigation.autoRevealFirstBlockingIssueIfNeeded(
                    issues: validationIssues,
                    lastAutoRevealedIssueID: &lastAutoRevealedIssueID,
                    expandedSectionIDs: $expandedValidationSections,
                    scrollProxy: scrollProxy
                )
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: medicationPlans.count)
        .onChange(of: medicationPlans) { newValue in
            syncMedicationPlansToViewModel(newValue)
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: attachments,
                selectedIDs: medicationPlans.indices.contains(target.index) ? medicationPlans[target.index].attachmentFileIds : [],
                onSubmit: { ids in
                    guard medicationPlans.indices.contains(target.index) else { return }
                    removeAttachmentIDs(ids, except: target.index)
                    medicationPlans[target.index].attachmentFileIds = ids
                }
            )
        }
    }

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
            .buttonStyle(.bordered)

            Button {
                logger.info("Medication result: submit save tapped meds=\(medicationPlans.count)", module: logModule)
                submitSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("medical.upload.result.common.submit")).frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || medicationPlans.isEmpty)
        }
    }

    private func submitSave() {
        syncMedicationPlansToViewModel(medicationPlans)
        Task { _ = await viewModel.saveResult() }
    }

    private func syncMedicationPlansToViewModel(_ plans: [MedicationPlanRecognitionDraft]) {
        viewModel.updateTypedResult(.medicationPlan(plans))
    }

    private func updateMedicationDraft(at index: Int, draft: MedicationPlanRecognitionDraft) {
        guard medicationPlans.indices.contains(index) else { return }
        medicationPlans[index] = draft
        logger.info("Medication result: local item updated index=\(index)", module: logModule)
    }

    private func deleteMedicationDraft(at index: Int) {
        guard medicationPlans.indices.contains(index) else { return }
        medicationPlans.remove(at: index)
        logger.info("Medication result: local item deleted index=\(index)", module: logModule)
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in medicationPlans.indices where index != targetIndex {
            medicationPlans[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
    }
}
