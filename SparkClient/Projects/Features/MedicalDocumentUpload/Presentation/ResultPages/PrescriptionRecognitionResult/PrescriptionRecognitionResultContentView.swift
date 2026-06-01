import SwiftUI

/// 处方单识别结果页面
/// 功能：展示AI识别的处方信息（医院、医生、诊断、药品清单）→ 支持编辑 → 保存
struct PrescriptionRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 处方草稿（核心数据：处方信息 + 药品列表）
    @State private var batch: PrescriptionRecognitionDraft
    /// 本地编辑弹窗（编辑处方 / 编辑单个药品）
    @State private var localEditor: PrescriptionResultLocalEditor?
    @State private var attachmentTarget: PrescriptionAttachmentTarget?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?
    /// 日志工具
    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    /// 初始化：从 AI 输出中提取处方数据
    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output

        // 从识别结果中取出处方数据，没有则创建空处方
        if case .prescription(let draft) = output.typedResult {
            _batch = State(initialValue: draft)
        } else {
            _batch = State(initialValue: PrescriptionRecognitionDraft(
                medicalCase: nil,
                prescriberName: nil,
                institutionName: nil,
                prescribedAt: nil,
                diagnosis: nil,
                prescriptionNo: nil,
                status: nil,
                extra: nil,
                medicationPlans: []
            ))
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }
    private var validationIssues: [MedicalPreSubmitValidationIssue] { viewModel.preSubmitValidationIssues }
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: output.envelope.memberID,
            viewModel: viewModel,
            logger: logger
        )
    }

    /// 附件（上传的处方照片）
    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(batch.associatedAttachmentFileIDs)
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

                // MARK: 1. 成员确认区域（归属哪个家庭成员）
                PrescriptionMemberConfirmSectionView(
                    memberID: output.envelope.memberID,
                    batch: batch
                )

                // MARK: 2. 处方内容 + 药品列表区域（核心）
                /// 展示：医院、医生、诊断、药品清单
                /// 支持：编辑整个处方 / 编辑单个药品
                PrescriptionBatchListSectionView(
                    batches: [batch],
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    attachmentsForIDs: matchedAttachments(for:),
                    detailNavigationContext: detailNavigationContext,
                    onEditBatch: { _, batch in
                        logger.info("Prescription result: open local batch editor", module: logModule)
                        localEditor = .batch(batch) // 打开处方编辑页
                    },
                    onEditMedication: { _, index, item in
                        logger.info("Prescription result: open local medication editor index=\(index)", module: logModule)
                        localEditor = .medication(index: index, draft: item) // 打开单个药品编辑页
                    },
                    onManageBatchAttachments: { _, _ in
                        attachmentTarget = .batch
                    },
                    onManageMedicationAttachments: { _, index, _ in
                        attachmentTarget = .medication(index: index)
                    }
                )

                // MARK: 3. 未关联业务的源文件附件
                MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                // MARK: 4. 保存成功回执（显示记录ID）
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
        // 底部固定工具栏：返回 + 保存
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        // 药品数量变化时动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batch.medicationPlans?.count ?? 0)
        // 编辑弹窗（全屏）
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

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 返回按钮
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
                .buttonStyle(.bordered)

            // 保存按钮
            Button {
                logger.info("Prescription result: submit save tapped", module: logModule)
                submitSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity) // 保存中显示转圈
                    } else {
                        Text(L10n.text("medical.upload.result.common.submit")).frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving) // 保存中禁用按钮
        }
    }

    private func submitSave() {
        viewModel.updateTypedResult(.prescription(batch))
        Task { _ = await viewModel.saveResult() }
    }

    private func attachmentIDs(for target: PrescriptionAttachmentTarget) -> [UUID] {
        switch target {
        case .batch:
            return batch.attachmentFileIds
        case .medication(let index):
            guard let meds = batch.medicationPlans, meds.indices.contains(index) else { return [] }
            return meds[index].attachmentFileIds
        }
    }

    private func applyAttachmentIDs(_ ids: [UUID], to target: PrescriptionAttachmentTarget) {
        removeAttachmentIDs(ids, except: target)

        switch target {
        case .batch:
            batch.attachmentFileIds = ids
        case .medication(let index):
            var meds = batch.medicationPlans ?? []
            guard meds.indices.contains(index) else { return }
            meds[index].attachmentFileIds = ids
            batch.medicationPlans = meds
        }
    }

    private func removeAttachmentIDs(_ ids: [UUID], except target: PrescriptionAttachmentTarget) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        if target.id != PrescriptionAttachmentTarget.batch.id {
            batch.attachmentFileIds.removeAll { idSet.contains($0) }
        }

        var meds = batch.medicationPlans ?? []
        for index in meds.indices where target.id != PrescriptionAttachmentTarget.medication(index: index).id {
            meds[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
        batch.medicationPlans = meds
    }

    // MARK: - 编辑页面路由
    /// 根据编辑类型，跳转到不同的编辑页面
    @ViewBuilder
    private func editorDestination(_ editor: PrescriptionResultLocalEditor) -> some View {
        switch editor {
        // 编辑【整张处方】
        case .batch(let existing):
            if let detailNavigationContext {
                MedicationPrescriptionEditPage(
                    mode: .localEdit(existing: existing, onSubmit: { updated in
                        logger.info("Prescription result: local batch updated meds=\(updated.medicationPlans?.count ?? 0)", module: logModule)
                        batch = updated
                    }),
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient
                )
            }

        // 编辑【单个药品】
        case .medication(let index, let med):
            if let detailNavigationContext {
                MedicationPlanFormView(
                    mode: .localEdit(existing: MedicationPlanDraft(recognition: med), onSubmit: { updatedDraft in
                        let updated = updatedDraft.recognitionDraft(preserving: med)
                        var meds = batch.medicationPlans ?? []
                        guard meds.indices.contains(index) else { return }
                        meds[index] = updated

                        batch = PrescriptionRecognitionDraft(
                            medicalCase: batch.medicalCase,
                            prescriberName: batch.prescriberName,
                            institutionName: batch.institutionName,
                            prescribedAt: batch.prescribedAt,
                            diagnosis: batch.diagnosis,
                            prescriptionNo: batch.prescriptionNo,
                            status: batch.status,
                            extra: batch.extra,
                            medicationPlans: meds,
                            attachmentFileIds: batch.attachmentFileIds
                        )
                        logger.info("Prescription result: local medication updated index=\(index)", module: logModule)
                    }),
                    memberID: detailNavigationContext.memberID,
                    medicineBoxes: [med.remoteMedicineBox(memberID: detailNavigationContext.memberID, id: -30_000 - index)],
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient,
                    onMedicineBoxSaved: { _ in }
                )
            }
        }
    }
}
