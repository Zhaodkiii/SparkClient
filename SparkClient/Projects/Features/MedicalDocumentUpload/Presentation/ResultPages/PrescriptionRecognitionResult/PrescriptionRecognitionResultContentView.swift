import SwiftUI

/// 处方单识别结果页面
/// 功能：展示 AI 识别的处方数组 → 成员切换 → 本地草稿编辑 → 保存
struct PrescriptionRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    let output: MedicalDocumentTypedExtractionOutput

    @State private var batches: [PrescriptionRecognitionDraft]
    @State private var selectedMemberID: Int?
    @State private var localEditor: PrescriptionResultLocalEditor?
    @State private var attachmentTarget: PrescriptionAttachmentTarget?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?

    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output
        _selectedMemberID = State(initialValue: output.envelope.memberID)

        if case .prescription(let drafts) = output.typedResult {
            _batches = State(initialValue: drafts)
        } else {
            _batches = State(initialValue: [])
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

    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(batches.associatedAttachmentFileIDs)
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

                PrescriptionMemberConfirmSectionView(
                    memberContextStore: viewModel.memberContextStoreForLocalForms,
                    selectedMemberID: selectedMemberID,
                    batches: batches,
                    onSelectMember: { memberID in
                        selectedMemberID = memberID
                        viewModel.updateResultMemberID(memberID)
                    }
                )

                PrescriptionBatchListSectionView(
                    batches: batches,
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    attachmentsForIDs: matchedAttachments(for:),
                    detailNavigationContext: detailNavigationContext,
                    onEditBatch: { index, batch in
                        logger.info("Prescription result: open local batch editor index=\(index)", module: logModule)
                        localEditor = .batch(index: index, batch: batch)
                    },
                    onEditMedication: { batchIndex, itemIndex, item in
                        logger.info("Prescription result: open local medication editor batch=\(batchIndex) index=\(itemIndex)", module: logModule)
                        localEditor = .medication(batchIndex: batchIndex, index: itemIndex, draft: item)
                    },
                    onUpdatePrescriptionDraft: updatePrescriptionDraft(at:draft:),
                    onDeletePrescriptionDraft: deletePrescriptionDraft(at:),
                    onUpdateMedicationDraft: updateMedicationDraft(prescriptionIndex:medicationIndex:draft:),
                    onDeleteMedicationDraft: deleteMedicationDraft(prescriptionIndex:medicationIndex:),
                    onManageBatchAttachments: { index, _ in
                        attachmentTarget = .batch(index: index)
                    },
                    onManageMedicationAttachments: { batchIndex, itemIndex, _ in
                        attachmentTarget = .medication(batchIndex: batchIndex, index: itemIndex)
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
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batches.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batches.reduce(0) { $0 + ($1.medicationPlans?.count ?? 0) })
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: attachments,
                selectedIDs: attachmentIDs(for: target),
                onSubmit: { applyAttachmentIDs($0, to: target) }
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
            .buttonStyle(.bordered)

            Button {
                logger.info("Prescription result: submit save tapped batches=\(batches.count)", module: logModule)
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
            .disabled(isSaving || batches.isEmpty)
        }
    }

    private func submitSave() {
        viewModel.updateTypedResult(.prescription(batches))
        Task { _ = await viewModel.saveResult() }
    }

    private func syncBatchesToViewModel() {
        viewModel.updateTypedResult(.prescription(batches))
    }

    private func updatePrescriptionDraft(at index: Int, draft: PrescriptionRecognitionDraft) {
        guard batches.indices.contains(index) else { return }
        batches[index] = draft
        syncBatchesToViewModel()
    }

    private func deletePrescriptionDraft(at index: Int) {
        guard batches.indices.contains(index) else { return }
        batches.remove(at: index)
        syncBatchesToViewModel()
    }

    private func updateMedicationDraft(
        prescriptionIndex: Int,
        medicationIndex: Int,
        draft: MedicationPlanRecognitionDraft
    ) {
        guard batches.indices.contains(prescriptionIndex) else { return }
        guard var plans = batches[prescriptionIndex].medicationPlans, plans.indices.contains(medicationIndex) else { return }
        plans[medicationIndex] = draft
        batches[prescriptionIndex].medicationPlans = plans
        syncBatchesToViewModel()
    }

    private func deleteMedicationDraft(prescriptionIndex: Int, medicationIndex: Int) {
        guard batches.indices.contains(prescriptionIndex) else { return }
        guard var plans = batches[prescriptionIndex].medicationPlans, plans.indices.contains(medicationIndex) else { return }
        plans.remove(at: medicationIndex)
        batches[prescriptionIndex].medicationPlans = plans
        syncBatchesToViewModel()
    }

    private func attachmentIDs(for target: PrescriptionAttachmentTarget) -> [UUID] {
        switch target {
        case .batch(let index):
            guard batches.indices.contains(index) else { return [] }
            return batches[index].attachmentFileIds
        case .medication(let batchIndex, let index):
            guard batches.indices.contains(batchIndex),
                  let meds = batches[batchIndex].medicationPlans,
                  meds.indices.contains(index)
            else { return [] }
            return meds[index].attachmentFileIds
        }
    }

    private func applyAttachmentIDs(_ ids: [UUID], to target: PrescriptionAttachmentTarget) {
        removeAttachmentIDs(ids, except: target)

        switch target {
        case .batch(let index):
            guard batches.indices.contains(index) else { return }
            batches[index].attachmentFileIds = ids
        case .medication(let batchIndex, let index):
            guard batches.indices.contains(batchIndex) else { return }
            var meds = batches[batchIndex].medicationPlans ?? []
            guard meds.indices.contains(index) else { return }
            meds[index].attachmentFileIds = ids
            batches[batchIndex].medicationPlans = meds
        }
        syncBatchesToViewModel()
    }

    private func removeAttachmentIDs(_ ids: [UUID], except target: PrescriptionAttachmentTarget) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for batchIndex in batches.indices {
            if target.id != PrescriptionAttachmentTarget.batch(index: batchIndex).id {
                batches[batchIndex].attachmentFileIds.removeAll { idSet.contains($0) }
            }
            var meds = batches[batchIndex].medicationPlans ?? []
            for medIndex in meds.indices where target.id != PrescriptionAttachmentTarget.medication(batchIndex: batchIndex, index: medIndex).id {
                meds[medIndex].attachmentFileIds.removeAll { idSet.contains($0) }
            }
            batches[batchIndex].medicationPlans = meds
        }
    }

    @ViewBuilder
    private func editorDestination(_ editor: PrescriptionResultLocalEditor) -> some View {
        switch editor {
        case .batch(let batchIndex, let existing):
            if let detailNavigationContext {
                MedicationPrescriptionEditPage(
                    mode: .localEdit(existing: existing, onSubmit: { updated in
                        logger.info("Prescription result: local batch updated index=\(batchIndex) meds=\(updated.medicationPlans?.count ?? 0)", module: logModule)
                        updatePrescriptionDraft(at: batchIndex, draft: updated)
                    }),
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient
                )
            }

        case .medication(let batchIndex, let index, let med):
            if let detailNavigationContext {
                MedicationPlanFormView(
                    mode: .localEdit(existing: MedicationPlanDraft(recognition: med), onSubmit: { updatedDraft in
                        let updated = updatedDraft.recognitionDraft(preserving: med)
                        updateMedicationDraft(prescriptionIndex: batchIndex, medicationIndex: index, draft: updated)
                        logger.info("Prescription result: local medication updated batch=\(batchIndex) index=\(index)", module: logModule)
                    }),
                    memberID: detailNavigationContext.memberID,
                    medicineBoxes: [med.remoteMedicineBox(
                        memberID: detailNavigationContext.memberID,
                        id: PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                            prescriptionIndex: batchIndex,
                            medicationIndex: index
                        )
                    )],
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient,
                    onMedicineBoxSaved: { _ in }
                )
            }
        }
    }
}
