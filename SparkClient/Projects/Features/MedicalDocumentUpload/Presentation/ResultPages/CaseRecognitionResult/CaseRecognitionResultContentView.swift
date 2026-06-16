
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
    @State private var attachmentTarget: CaseRecognitionAttachmentTarget?
    @State private var deletionTarget: CaseRecognitionLocalEditor?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?

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
    private var validationIssues: [MedicalPreSubmitValidationIssue] { viewModel.preSubmitValidationIssues }
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: output.envelope.memberID,
            viewModel: viewModel,
            logger: ConsoleLogger()
        )
    }

    /// 附件：上传的病历照片 / 扫描件
    private var localAttachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return localAttachments.filter { idSet.contains($0.id) }
    }

    /// 尚未关联到病历任意业务条目的源文件附件
    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        localAttachments.excludingAssociatedIDs(draft.associatedAttachmentFileIDs)
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

                // MARK: 1. 成员信息区域（归属家庭成员）
                CaseMemberInfoSectionView(
                    memberID: output.envelope.memberID,
                    draft: draft,
                    validationIssues: validationIssues
                )

                // MARK: 2. 病史 & 诊断区域
                CaseHistoryDiagnosisSectionView(
                    draft: draft,
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    caseAttachments: matchedAttachments(for: draft.attachmentFileIds),
                    symptomAttachments: matchedAttachments(for: draft.symptom?.attachmentFileIds ?? []),
                    visitAttachments: matchedAttachments(for: draft.visit?.attachmentFileIds ?? []),
                    surgeryAttachments: matchedAttachments(for: draft.surgery?.attachmentFileIds ?? []),
                    onEditCase: { localEditor = .caseDraft(caseFormDraft) }, // 编辑病例主档
                    onEditSymptom: { localEditor = .symptom($0) },    // 编辑症状
                    onEditVisit: { localEditor = .visit($0) },          // 编辑就诊记录
                    onEditSurgery: { localEditor = .surgery($0) },     // 编辑手术史
                    onManageCaseAttachments: { attachmentTarget = .caseDraft },
                    onManageSymptomAttachments: { attachmentTarget = .symptom },
                    onManageVisitAttachments: { attachmentTarget = .visit },
                    onManageSurgeryAttachments: { attachmentTarget = .surgery }
                )

                // MARK: 4. 检查报告列表区域
                MedicalReportCardsSectionView(
                    reports: draft.examinationReports ?? [],
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    attachmentsForIDs: matchedAttachments(for:),
                    detailNavigationContext: detailNavigationContext,
                    onEdit: { index, report in
                        localEditor = .exam(index: index, draft: report) // 编辑单份检查报告
                    },
                    onManageAttachments: { index, _ in
                        attachmentTarget = .exam(index: index)
                    }
                )

                // MARK: 5. 治疗方案区域（处方 + 用药 + 随访）
                CaseTreatmentPlanSectionView(
                    batches: draft.prescriptions ?? [],
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    followUps: draft.followUps ?? [],
                    attachmentsForIDs: matchedAttachments(for:),
                    onEditBatch: { localEditor = .medicationBatch($0) },        // 编辑整张开方
                    onEditMedicationItem: { batchIndex, itemIndex, item in       // 编辑单个药品
                        localEditor = .medicationItem(batchIndex: batchIndex, itemIndex: itemIndex, draft: item)
                    },
                    onEditFollowUp: { localEditor = .followUp($0) },             // 编辑随访计划
                    detailNavigationContext: detailNavigationContext,
                    onManageBatchAttachments: { index, _ in
                        attachmentTarget = .prescription(index: index)
                    },
                    onManageMedicationAttachments: { batchIndex, itemIndex, _ in
                        attachmentTarget = .medication(batchIndex: batchIndex, itemIndex: itemIndex)
                    },
                    onManageFollowUpAttachments: { index, _ in
                        attachmentTarget = .followUp(index: index)
                    }
                )

                // MARK: 6. 未关联业务的源文件附件
                MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

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
        // 数据变化时动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draft.infoDensityCount)
        // 全屏编辑弹窗
        .sheet(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                localEditorDestination(editor)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Group {
                                if editor.allowsDeletion {
                                    Button(role: .destructive) {
                                        deletionTarget = editor
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .alert("确认删除？", isPresented: deleteConfirmationBinding) {
                        Button("删除", role: .destructive) {
                            if let deletionTarget {
                                deleteEditor(deletionTarget)
                            }
                            deletionTarget = nil
                            localEditor = nil
                        }
                        Button("取消", role: .cancel) {
                            deletionTarget = nil
                        }
                    } message: {
                        Text("删除后将从本次识别结果中移除此项。")
                    }
            }
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: localAttachments,
                selectedIDs: attachmentIDs(for: target),
                onSubmit: { applyAttachmentIDs($0, to: target) }
            )
        }
    }

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("返回") {
                viewModel.reset(keepAttachments: true)
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

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletionTarget != nil },
            set: { isPresented in
                if isPresented == false {
                    deletionTarget = nil
                }
            }
        )
    }

    private var caseFormDraft: MedicalCaseFormDraft {
        MedicalCaseFormDraft(
            memberID: output.envelope.memberID ?? viewModel.memberContextStoreForLocalForms.context.selectedMember?.id ?? 0,
            title: draft.title,
            hospitalName: draft.hospitalName ?? "",
            diagnosisSummary: draft.diagnosis ?? draft.summary ?? "",
            visitDate: MedicalDateCoding.decodeDateOnlyOrDefaultNow(
                draft.occurredAt ?? draft.visit?.visitedAt,
                defaultDate: Date()
            ),
            presentIllness: draft.summary ?? "",
            pastHistory: draft.surgery?.notes ?? "",
            ageAtVisit: draft.ageAtVisit.parsedAsAgeAtVisitInteger()
        )
    }

    private func applyCaseFormDraft(_ updated: MedicalCaseFormDraft) {
        draft = CaseRecognitionDraft(
            title: updated.title,
            summary: updated.presentIllness.nilIfBlank,
            diagnosis: updated.diagnosisSummary.nilIfBlank,
            hospitalName: updated.hospitalName.nilIfBlank,
            ageAtVisit: updated.ageAtVisit.map(String.init),
            occurredAt: MedicalDateCoding.encodeDateOnly(updated.visitDate),
            attachmentFileIds: draft.attachmentFileIds,
            symptom: draft.symptom,
            visit: draft.visit,
            surgery: draft.surgery,
            followUps: draft.followUps,
            prescriptions: draft.prescriptions,
            examinationReports: draft.examinationReports
        )
    }

    private func deleteEditor(_ editor: CaseRecognitionLocalEditor) {
        switch editor {
        case .caseDraft:
            return
        case .visit:
            draft.visit = nil
        case .symptom:
            draft.symptom = nil
        case .surgery:
            draft.surgery = nil
        case .medicationBatch(let batchDraft):
            var prescriptions = draft.prescriptions ?? []
            prescriptions.removeAll { $0 == batchDraft }
            draft.prescriptions = prescriptions
        case .medicationItem(let batchIndex, let itemIndex, _):
            guard var prescriptions = draft.prescriptions,
                  prescriptions.indices.contains(batchIndex),
                  var medications = prescriptions[batchIndex].medicationPlans,
                  medications.indices.contains(itemIndex)
            else { return }
            medications.remove(at: itemIndex)
            prescriptions[batchIndex].medicationPlans = medications
            draft.prescriptions = prescriptions
        case .followUp(let followDraft):
            var followUps = draft.followUps ?? []
            followUps.removeAll { $0 == followDraft }
            draft.followUps = followUps
        case .exam(let index, _):
            guard var reports = draft.examinationReports, reports.indices.contains(index) else { return }
            reports.remove(at: index)
            draft.examinationReports = reports
        }
    }

    private func attachmentIDs(for target: CaseRecognitionAttachmentTarget) -> [UUID] {
        switch target {
        case .caseDraft:
            return draft.attachmentFileIds
        case .symptom:
            return draft.symptom?.attachmentFileIds ?? []
        case .surgery:
            return draft.surgery?.attachmentFileIds ?? []
        case .visit:
            return draft.visit?.attachmentFileIds ?? []
        case .exam(let index):
            guard let reports = draft.examinationReports, reports.indices.contains(index) else { return [] }
            return reports[index].attachmentFileIds
        case .prescription(let index):
            guard let prescriptions = draft.prescriptions, prescriptions.indices.contains(index) else { return [] }
            return prescriptions[index].attachmentFileIds
        case .medication(let batchIndex, let itemIndex):
            guard let prescriptions = draft.prescriptions,
                  prescriptions.indices.contains(batchIndex),
                  let medications = prescriptions[batchIndex].medicationPlans,
                  medications.indices.contains(itemIndex)
            else { return [] }
            return medications[itemIndex].attachmentFileIds
        case .followUp(let index):
            guard let followUps = draft.followUps, followUps.indices.contains(index) else { return [] }
            return followUps[index].attachmentFileIds
        }
    }

    private func applyAttachmentIDs(_ ids: [UUID], to target: CaseRecognitionAttachmentTarget) {
        removeAttachmentIDs(ids, except: target)

        switch target {
        case .caseDraft:
            draft.attachmentFileIds = ids
        case .symptom:
            var symptom = draft.symptom
            symptom?.attachmentFileIds = ids
            draft.symptom = symptom
        case .surgery:
            var surgery = draft.surgery
            surgery?.attachmentFileIds = ids
            draft.surgery = surgery
        case .visit:
            var visit = draft.visit
            visit?.attachmentFileIds = ids
            draft.visit = visit
        case .exam(let index):
            guard var reports = draft.examinationReports, reports.indices.contains(index) else { return }
            reports[index].attachmentFileIds = ids
            draft.examinationReports = reports
        case .prescription(let index):
            guard var prescriptions = draft.prescriptions, prescriptions.indices.contains(index) else { return }
            prescriptions[index].attachmentFileIds = ids
            draft.prescriptions = prescriptions
        case .medication(let batchIndex, let itemIndex):
            guard var prescriptions = draft.prescriptions,
                  prescriptions.indices.contains(batchIndex),
                  var medications = prescriptions[batchIndex].medicationPlans,
                  medications.indices.contains(itemIndex)
            else { return }
            medications[itemIndex].attachmentFileIds = ids
            prescriptions[batchIndex].medicationPlans = medications
            draft.prescriptions = prescriptions
        case .followUp(let index):
            guard var followUps = draft.followUps, followUps.indices.contains(index) else { return }
            followUps[index].attachmentFileIds = ids
            draft.followUps = followUps
        }
    }

    private func removeAttachmentIDs(_ ids: [UUID], except target: CaseRecognitionAttachmentTarget) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        if target.id != CaseRecognitionAttachmentTarget.caseDraft.id {
            draft.attachmentFileIds.removeAll { idSet.contains($0) }
        }

        if target.id != CaseRecognitionAttachmentTarget.symptom.id {
            draft.symptom?.attachmentFileIds.removeAll { idSet.contains($0) }
        }

        if target.id != CaseRecognitionAttachmentTarget.surgery.id {
            draft.surgery?.attachmentFileIds.removeAll { idSet.contains($0) }
        }

        if target.id != CaseRecognitionAttachmentTarget.visit.id {
            draft.visit?.attachmentFileIds.removeAll { idSet.contains($0) }
        }

        if var reports = draft.examinationReports {
            for index in reports.indices where target.id != CaseRecognitionAttachmentTarget.exam(index: index).id {
                reports[index].attachmentFileIds.removeAll { idSet.contains($0) }
            }
            draft.examinationReports = reports
        }

        if var prescriptions = draft.prescriptions {
            for batchIndex in prescriptions.indices {
                if target.id != CaseRecognitionAttachmentTarget.prescription(index: batchIndex).id {
                    prescriptions[batchIndex].attachmentFileIds.removeAll { idSet.contains($0) }
                }

                if var medications = prescriptions[batchIndex].medicationPlans {
                    for itemIndex in medications.indices where target.id != CaseRecognitionAttachmentTarget.medication(batchIndex: batchIndex, itemIndex: itemIndex).id {
                        medications[itemIndex].attachmentFileIds.removeAll { idSet.contains($0) }
                    }
                    prescriptions[batchIndex].medicationPlans = medications
                }
            }
            draft.prescriptions = prescriptions
        }

        if var followUps = draft.followUps {
            for index in followUps.indices where target.id != CaseRecognitionAttachmentTarget.followUp(index: index).id {
                followUps[index].attachmentFileIds.removeAll { idSet.contains($0) }
            }
            draft.followUps = followUps
        }
    }

    // MARK: - 编辑页面路由（支持8种精细化编辑）
    @ViewBuilder
    private func localEditorDestination(_ editor: CaseRecognitionLocalEditor) -> some View {
        switch editor {
        // 1. 编辑病历文档
        case .caseDraft(let caseDraft):
            if let workflowAPI = viewModel.workflowAPIForCaseLocalForms {
                MedicalCaseFormView(
                    mode: .localEdit(caseDraft, onDone: applyCaseFormDraft),
                    memberContextStore: viewModel.memberContextStoreForLocalForms,
                    workflowAPI: workflowAPI,
                    notificationClient: viewModel.notificationClientForLocalForms ?? CaseRecognitionNoopNotificationClient.shared
                )
            }

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
            if let detailNavigationContext {
                MedicationPrescriptionEditPage(
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
                    }),
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient
                )
            }
        // 5. 编辑处方中的单个药品
        case .medicationItem(let batchIndex, let itemIndex, let medDraft):
            if let detailNavigationContext {
                MedicationPlanStepperView(
                    mode: .localEdit(existing: MedicationPlanDraft(recognition: medDraft), onSubmit: { updatedDraft in
                        let updated = updatedDraft.recognitionDraft(preserving: medDraft)
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
                    }),
                    memberID: detailNavigationContext.memberID,
                    medicineBoxes: [medDraft.remoteMedicineBox(memberID: detailNavigationContext.memberID, id: -30_000 - batchIndex * 100 - itemIndex)],
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient,
                    onMedicineBoxSaved: { _ in }
                )
            }

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

@MainActor
private final class CaseRecognitionNoopNotificationClient: NotificationClient {
    static let shared = CaseRecognitionNoopNotificationClient()

    func publish(_ intent: NotificationIntent) {}
    func success(_ message: String, title: String?, source: String) {}
    func error(_ message: String, title: String?, source: String) {}
    func warning(_ message: String, title: String?, source: String) {}
    func info(_ message: String, title: String?, source: String) {}
}
