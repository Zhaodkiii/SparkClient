import SwiftUI

struct CaseRecognitionResultContentView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    @State private var draft: CaseRecognitionDraft
    @State private var localEditor: CaseRecognitionLocalEditor?

    init(
        output: MedicalDocumentTypedExtractionOutput,
        isSaving: Bool,
        saveReceipt: MedicalDocumentSaveReceipt?,
        onBack: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.output = output
        self.isSaving = isSaving
        self.saveReceipt = saveReceipt
        self.onBack = onBack
        self.onSave = onSave

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
                prescriptionBatches: nil,
                examinationReports: nil
            ))
        }
    }

    private var localAttachments: [CaseLocalAttachmentItem] {
        output.envelope.sourceFiles.map { CaseLocalAttachmentItem(file: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CaseMemberInfoSectionView(
                    memberID: output.envelope.memberID,
                    draft: draft
                )

                CaseHistoryDiagnosisSectionView(
                    draft: draft,
                    onEditSymptom: { localEditor = .symptom($0) },
                    onEditSurgery: { localEditor = .surgery($0) }
                )

                CaseVisitInfoSectionView(
                    visit: draft.visit,
                    onEdit: { localEditor = .visit($0) }
                )

                CaseExamReportsSectionView(
                    reports: draft.examinationReports ?? [],
                    onEdit: { index, report in
                        localEditor = .exam(index: index, draft: report)
                    }
                )

                CaseTreatmentPlanSectionView(
                    batches: draft.prescriptionBatches ?? [],
                    followUps: draft.followUps ?? [],
                    onEditBatch: { localEditor = .medicationBatch($0) },
                    onEditMedicationItem: { batchIndex, itemIndex, item in
                        localEditor = .medicationItem(batchIndex: batchIndex, itemIndex: itemIndex, draft: item)
                    },
                    onEditFollowUp: { localEditor = .followUp($0) }
                )

                CaseAttachmentsSectionView(attachments: localAttachments)

                if let saveReceipt {
                    CaseSectionCard(
                        title: "保存状态",
                        subtitle: "已提交到后端",
                        systemImage: "checkmark.circle",
                        badgeText: "成功"
                    ) {
                        CaseInfoLine(title: "记录 ID", value: "\(saveReceipt.recordID)")
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draft.infoDensityCount)
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                localEditorDestination(editor)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("返回", action: onBack)
                .buttonStyle(.bordered)

            Button {
                onSave()
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

    @ViewBuilder
    private func localEditorDestination(_ editor: CaseRecognitionLocalEditor) -> some View {
        switch editor {
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
                        symptom: draft.symptom,
                        visit: updated,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptionBatches: draft.prescriptionBatches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

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
                        symptom: updated,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptionBatches: draft.prescriptionBatches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

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
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: updated,
                        followUps: draft.followUps,
                        prescriptionBatches: draft.prescriptionBatches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        case .medicationBatch(let batchDraft):
            MedicationMultiCreateView(
                mode: .localEdit(existing: batchDraft, onSubmit: { updated in
                    var items = draft.prescriptionBatches ?? []
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
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptionBatches: items,
                        examinationReports: draft.examinationReports
                    )
                })
            )

        case .medicationItem(let batchIndex, let itemIndex, let medDraft):
            MedicationFormView(
                mode: .localEdit(existing: medDraft, onSubmit: { updated in
                    var batches = draft.prescriptionBatches ?? []
                    guard batches.indices.contains(batchIndex) else { return }
                    var batch = batches[batchIndex]
                    var meds = batch.medications ?? []
                    guard meds.indices.contains(itemIndex) else { return }
                    meds[itemIndex] = updated
                    batch = PrescriptionRecognitionDraft(
                        medicalCase: batch.medicalCase,
                        prescriberName: batch.prescriberName,
                        institutionName: batch.institutionName,
                        prescribedAt: batch.prescribedAt,
                        diagnosis: batch.diagnosis,
                        batchNo: batch.batchNo,
                        status: batch.status,
                        auditorName: batch.auditorName,
                        auditedAt: batch.auditedAt,
                        extra: batch.extra,
                        medications: meds
                    )
                    batches[batchIndex] = batch
                    draft = CaseRecognitionDraft(
                        title: draft.title,
                        summary: draft.summary,
                        diagnosis: draft.diagnosis,
                        hospitalName: draft.hospitalName,
                        ageAtVisit: draft.ageAtVisit,
                        occurredAt: draft.occurredAt,
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptionBatches: batches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

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
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: followUps,
                        prescriptionBatches: draft.prescriptionBatches,
                        examinationReports: draft.examinationReports
                    )
                })
            )

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
                        symptom: draft.symptom,
                        visit: draft.visit,
                        surgery: draft.surgery,
                        followUps: draft.followUps,
                        prescriptionBatches: draft.prescriptionBatches,
                        examinationReports: reports
                    )
                })
            )
        }
    }
}
