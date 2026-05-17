
import SwiftUI

/// 【病历/病例文档】识别结果页面
/// 功能：AI 识别完整病历 → 展示就诊全流程信息 → 支持精细化编辑 → 保存
/// 这是医疗模块中数据最全、结构最复杂的结果页
struct CaseRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取输出结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 病历草稿（单例对象，一份上传对应一份完整病历）
    @State private var draft: CaseRecognitionDraft
    /// 本地编辑弹窗（支持多达8种编辑项：症状/就诊/手术/报告/处方/药品/随访等）
    @State private var localEditor: CaseRecognitionLocalEditor?

    /// 初始化：从 AI 识别结果中加载病历数据
    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output

        // 从识别结果中加载病历，无数据则创建默认空病历
        if case .caseDocument(let caseDraft) = output.typedResult {
            _draft = State(initialValue: caseDraft)
        } else {
            _draft = State(initialValue: CaseRecognitionDraft(
                title: "未识别到病例",
                summary: nil,
                diagnosis: nil,
                hospitalName: nil,
                ageAtVisit: nil,
                occurredAt: nil,
                symptom: nil,
                visit: nil,
                surgery: nil,
                followUps: nil,
                prescriptions: nil,
                examinationReports: nil
            ))
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }

    /// 附件：上传的病历照片 / 扫描件
    private var localAttachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return localAttachments.filter { idSet.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: 1. 成员信息区域（归属家庭成员）
                CaseMemberInfoSectionView(
                    memberID: output.envelope.memberID,
                    draft: draft
                )

                // MARK: 2. 病史 & 诊断区域
                CaseHistoryDiagnosisSectionView(
                    draft: draft,
                    caseAttachments: matchedAttachments(for: draft.attachmentFileIds),
                    symptomAttachments: matchedAttachments(for: draft.symptom?.attachmentFileIds ?? []),
                    surgeryAttachments: matchedAttachments(for: draft.surgery?.attachmentFileIds ?? []),
                    onEditSymptom: { localEditor = .symptom($0) },    // 编辑症状
                    onEditSurgery: { localEditor = .surgery($0) }     // 编辑手术史
                )

                // MARK: 3. 就诊信息区域
                CaseVisitInfoSectionView(
                    visit: draft.visit,
                    attachments: matchedAttachments(for: draft.visit?.attachmentFileIds ?? []),
                    onEdit: { localEditor = .visit($0) }              // 编辑就诊记录
                )

                // MARK: 4. 检查报告列表区域
                MedicalReportCardsSectionView(
                    reports: draft.examinationReports ?? [],
                    attachmentsForIDs: matchedAttachments(for:),
                    onEdit: { index, report in
                        localEditor = .exam(index: index, draft: report) // 编辑单份检查报告
                    }
                )

                // MARK: 5. 治疗方案区域（处方 + 用药 + 随访）
                CaseTreatmentPlanSectionView(
                    batches: draft.prescriptions ?? [],
                    followUps: draft.followUps ?? [],
                    attachmentsForIDs: matchedAttachments(for:),
                    onEditBatch: { localEditor = .medicationBatch($0) },        // 编辑整张开方
                    onEditMedicationItem: { batchIndex, itemIndex, item in       // 编辑单个药品
                        localEditor = .medicationItem(batchIndex: batchIndex, itemIndex: itemIndex, draft: item)
                    },
                    onEditFollowUp: { localEditor = .followUp($0) }             // 编辑随访计划
                )

                // MARK: 6. 附件展示（病历原图）
                CaseAttachmentsSectionView(attachments: localAttachments)

                // MARK: 7. 保存成功回执（显示记录ID）
                if let saveReceipt {
                    MedicalDocumentResultSectionCard(
                        title: "保存状态",
                        subtitle: "已提交到后端",
                        systemImage: "checkmark.circle",
                        badgeText: "成功"
                    ) {
                        MedicalDocumentResultInfoLine(title: "记录 ID", value: "\(saveReceipt.recordID)")
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
        // 数据变化时动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draft.infoDensityCount)
        // 全屏编辑弹窗
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                localEditorDestination(editor)
            }
        }
    }

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("返回") {
                viewModel.reset()
            }
                .buttonStyle(.bordered)

            Button {
                submitSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("提交保存").frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
    }

    private func submitSave() {
        viewModel.updateTypedResult(.caseDocument(draft))
        Task { _ = await viewModel.saveResult() }
    }

    // MARK: - 编辑页面路由（支持8种精细化编辑）
    @ViewBuilder
    private func localEditorDestination(_ editor: CaseRecognitionLocalEditor) -> some View {
        switch editor {
        // 1. 编辑就诊信息
        case .visit(let visitDraft):
            VisitFormView(
                mode: .localEdit(existing: visitDraft, onSubmit: { updated in
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: updated,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptions: draft.prescriptions,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 2. 编辑症状
        case .symptom(let symptomDraft):
            SymptomFormView(
                mode: .localEdit(existing: symptomDraft, onSubmit: { updated in
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: updated,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptions: draft.prescriptions,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 3. 编辑手术史
        case .surgery(let surgeryDraft):
            SurgeryFormView(
                mode: .localEdit(existing: surgeryDraft, onSubmit: { updated in
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: updated,
                        followUps: draft.followUps,
                        prescriptions: draft.prescriptions,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 4. 编辑整组处方
        case .medicationBatch(let batchDraft):
            MedicationMultiCreateView(
                mode: .localEdit(existing: batchDraft, onSubmit: { updated in
                    var items = draft.prescriptions ?? []
                    if let index = items.firstIndex(of: batchDraft) {
                        items[index] = updated
                    }
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptions: items,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 5. 编辑处方中的单个药品
        case .medicationItem(let batchIndex, let itemIndex, let medDraft):
            MedicationFormView(
                mode: .localEdit(existing: medDraft, onSubmit: { updated in
                    var batches = draft.prescriptions ?? []
                    guard batches.indices.contains(batchIndex) else { return }
                    var batch = batches[batchIndex]
                    var meds = batch.medicationPlans ?? []
                    guard meds.indices.contains(itemIndex) else { return }
                    meds[itemIndex] = updated
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
                    batches[batchIndex] = batch
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptions: batches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 6. 编辑随访计划
        case .followUp(let followDraft):
            FollowUpFormView(
                mode: .localEdit(existing: followDraft, onSubmit: { updated in
                    var followUps = draft.followUps ?? []
                    if let index = followUps.firstIndex(of: followDraft) {
                        followUps[index] = updated
                    }
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: followUps,
                        prescriptions: draft.prescriptions,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        // 7. 编辑检查报告
        case .exam(let index, let examDraft):
            ExamReportFormView(
                mode: .localEdit(existing: examDraft, onSubmit: { updated in
                    var reports = draft.examinationReports ?? []
                    guard reports.indices.contains(index) else { return }
                    reports[index] = updated
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        attachmentFileIds: draft.attachmentFileIds,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptions: draft.prescriptions,
                        examinationReports: reports
                    )
                })
            )
        }
    }
}
