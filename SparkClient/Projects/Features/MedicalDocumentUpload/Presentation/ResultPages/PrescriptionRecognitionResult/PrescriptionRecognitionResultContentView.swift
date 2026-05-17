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

    /// 附件（上传的处方照片）
    private var attachments: [PrescriptionResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { PrescriptionResultLocalAttachmentItem(file: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: 1. 成员确认区域（归属哪个家庭成员）
                PrescriptionMemberConfirmSectionView(
                    memberID: output.envelope.memberID,
                    batch: batch
                )

                // MARK: 2. 处方内容 + 药品列表区域（核心）
                /// 展示：医院、医生、诊断、药品清单
                /// 支持：编辑整个处方 / 编辑单个药品
                PrescriptionBatchListSectionView(
                    batch: batch,
                    onEditBatch: {
                        logger.info("Prescription result: open local batch editor", module: logModule)
                        localEditor = .batch(batch) // 打开处方编辑页
                    },
                    onEditMedication: { index, item in
                        logger.info("Prescription result: open local medication editor index=\(index)", module: logModule)
                        localEditor = .medication(index: index, draft: item) // 打开单个药品编辑页
                    }
                )

                // MARK: 3. 附件（处方照片）
                PrescriptionAttachmentsSectionView(attachments: attachments)

                // MARK: 4. 保存成功回执（显示记录ID）
                if let saveReceipt {
                    PrescriptionResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        PrescriptionResultInfoLine(
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
        // 药品数量变化时动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batch.medicationPlans?.count ?? 0)
        // 编辑弹窗（全屏）
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
        }
    }

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 返回按钮
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset()
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

    // MARK: - 编辑页面路由
    /// 根据编辑类型，跳转到不同的编辑页面
    @ViewBuilder
    private func editorDestination(_ editor: PrescriptionResultLocalEditor) -> some View {
        switch editor {
        // 编辑【整张处方】
        case .batch(let existing):
            MedicationMultiCreateView(
                mode: .localEdit(existing: existing, onSubmit: { updated in
                    logger.info("Prescription result: local batch updated meds=\(updated.medicationPlans?.count ?? 0)", module: logModule)
                    batch = updated // 保存编辑后的处方
                })
            )

        // 编辑【单个药品】
        case .medication(let index, let med):
            MedicationFormView(
                mode: .localEdit(existing: med, onSubmit: { updated in
                    var meds = batch.medicationPlans ?? []
                    guard meds.indices.contains(index) else { return }
                    meds[index] = updated // 更新对应位置的药品
                    
                    // 重新组装处方数据
                    batch = PrescriptionRecognitionDraft(
                        medicalCase: batch.medicalCase,
                        prescriberName: batch.prescriberName,
                        institutionName: batch.institutionName,
                        prescribedAt: batch.prescribedAt,
                        diagnosis: batch.diagnosis,
                        prescriptionNo: batch.prescriptionNo,
                        status: batch.status,
                        extra: batch.extra,
                        medicationPlans: meds
                    )
                    logger.info("Prescription result: local medication updated index=\(index)", module: logModule)
                })
            )
        }
    }
}
