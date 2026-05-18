import SwiftUI

/// 用药方案 / 服药计划 识别结果页面
/// 功能：展示AI识别的【用药计划】（药品 + 用法用量 + 服用时长）→ 支持编辑 → 保存
struct MedicationRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 用药方案列表（核心：药品 + 怎么吃 + 吃多久）
    @State private var medicationPlans: [MedicationPlanRecognitionDraft]
    /// 本地编辑弹窗（批量编辑 / 单个药品编辑）
    @State private var localEditor: MedicationResultLocalEditor?
    @State private var attachmentTarget: MedicationAttachmentTarget?

    /// 日志工具
    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    /// 初始化：从 AI 输出中提取【用药计划】数据
    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output

        // 从识别结果中取出用药计划，无数据则为空数组
        if case .medicationPlan(let meds) = output.typedResult {
            _medicationPlans = State(initialValue: meds)
        } else {
            _medicationPlans = State(initialValue: [])
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: output.envelope.memberID,
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

    /// 合成一个虚拟处方（为了复用已有的批量编辑页面）
    /// 把用药计划包装成 PrescriptionRecognitionDraft，兼容旧的编辑组件
    private var syntheticBatch: PrescriptionRecognitionDraft {
        PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: nil,
            prescribedAt: nil,
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: medicationPlans
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: 1. 成员确认区域（归属哪个家庭成员）
                MedicationMemberConfirmSectionView(
                    memberID: output.envelope.memberID,
                    medications: medicationPlans
                )

                // MARK: 2. 用药计划列表（核心展示区）
                /// 展示所有识别出的用药方案
                /// 支持：批量编辑全部药品 / 编辑单个药品
                MedicationListSectionView(
                    medications: medicationPlans,
                    attachmentsForIDs: matchedAttachments(for:),
                    onBatchEdit: {
                        logger.info("Medication result: open local batch editor", module: logModule)
                        localEditor = .batch(syntheticBatch) // 打开批量编辑
                    },
                    onEditItem: { index, item in
                        logger.info("Medication result: open local item editor index=\(index)", module: logModule)
                        localEditor = .item(index: index, draft: item) // 打开单个编辑
                    },
                    onManageAttachments: { index, _ in
                        attachmentTarget = MedicationAttachmentTarget(index: index)
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
            tintColor: Color(uiColor: .systemTeal),
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
        .background(Color(uiColor: .systemGroupedBackground))
        // 底部固定工具栏：返回 + 保存
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        // 药品数量变化动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: medicationPlans.count)
        // 全屏编辑弹窗
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
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
            // 返回按钮
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
                .buttonStyle(.bordered)

            // 保存按钮
            Button {
                logger.info("Medication result: submit save tapped", module: logModule)
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
            .disabled(isSaving) // 保存中禁用
        }
    }

    private func submitSave() {
        viewModel.updateTypedResult(.medicationPlan(medicationPlans))
        Task { _ = await viewModel.saveResult() }
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in medicationPlans.indices where index != targetIndex {
            medicationPlans[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
    }

    // MARK: - 编辑页面路由
    @ViewBuilder
    private func editorDestination(_ editor: MedicationResultLocalEditor) -> some View {
        switch editor {
        // 批量编辑（复用处方编辑页）
        case .batch(let batch):
            if let detailNavigationContext {
                MedicationPrescriptionEditPage(
                    mode: .localEdit(existing: batch, onSubmit: { updated in
                        medicationPlans = updated.medicationPlans ?? []
                        logger.info("Medication result: local batch updated meds=\(medicationPlans.count)", module: logModule)
                    }),
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient
                )
            }

        // 编辑单个用药计划
        case .item(let index, let item):
            if let detailNavigationContext {
                MedicationPlanFormView(
                    mode: .localEdit(existing: MedicationPlanDraft(recognition: item), onSubmit: { updatedDraft in
                        guard medicationPlans.indices.contains(index) else { return }
                        medicationPlans[index] = updatedDraft.recognitionDraft(preserving: item)
                        logger.info("Medication result: local item updated index=\(index)", module: logModule)
                    }),
                    memberID: detailNavigationContext.memberID,
                    medicineBoxes: [item.remoteMedicineBox(memberID: detailNavigationContext.memberID, id: -30_000 - index)],
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient,
                    onMedicineBoxSaved: { _ in }
                )
            }
        }
    }
}
