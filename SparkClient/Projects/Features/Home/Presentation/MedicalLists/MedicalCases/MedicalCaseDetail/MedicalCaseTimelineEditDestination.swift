import SwiftUI

/// `NavigationLink` 目标：表单 + 删除壳。
struct MedicalCaseTimelineEditDestination: View {
    let route: MedicalCaseTimelineEditRoute
    let memberID: Int
    let medicalCaseID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let eventID: String
    let onRecordRemoved: (String) -> Void

    var body: some View {
        switch route {
        case .prescription(let batch):
            MedicalTimelineDeleteShell(
                resourceKind: .prescriptionBatches,
                resourceID: batch.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                MedicationMultiCreateView(
                    mode: .serverEdit(
                        existing: MedicalCaseTimelineRemoteMapping.prescriptionDraft(
                            from: batch,
                            medicalCaseID: medicalCaseID
                        )
                    ),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitPrescriptionBatchUpdate(existingBatch: batch, memberID: memberID, draft: draft)
                    }
                )
            }

        case .standaloneMedication(let remote):
            MedicalTimelineDeleteShell(
                resourceKind: .medications,
                resourceID: remote.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                MedicationFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.medicationDraft(from: remote)),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitMedicationUpdate(memberID: memberID, existing: remote, draft: draft)
                    }
                )
            }

        case .examination(let report, _):
            MedicalTimelineDeleteShell(
                resourceKind: .examinationReports,
                resourceID: report.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                ExamReportFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.examinationDraft(from: report)),
                    onServerSubmit: { draft in
                        try await ExaminationReportServerMutationService(resources: workflowAPI)
                            .updateReport(report: report, draft: draft)
                    }
                )
            }

        case .symptom(let remote):
            MedicalTimelineDeleteShell(
                resourceKind: .symptoms,
                resourceID: remote.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                SymptomFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.symptomDraft(from: remote)),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitSymptomUpdate(memberID: memberID, existing: remote, draft: draft)
                    }
                )
            }

        case .visit(let remote):
            MedicalTimelineDeleteShell(
                resourceKind: .visits,
                resourceID: remote.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                VisitFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.visitDraft(from: remote)),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitVisitUpdate(memberID: memberID, existing: remote, draft: draft)
                    }
                )
            }

        case .surgery(let remote):
            MedicalTimelineDeleteShell(
                resourceKind: .surgeries,
                resourceID: remote.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                SurgeryFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.surgeryDraft(from: remote)),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitSurgeryUpdate(memberID: memberID, existing: remote, draft: draft)
                    }
                )
            }

        case .followUp(let remote):
            MedicalTimelineDeleteShell(
                resourceKind: .followUps,
                resourceID: remote.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                FollowUpFormView(
                    mode: .serverEdit(existing: MedicalCaseTimelineRemoteMapping.followUpDraft(from: remote)),
                    onServerSubmit: { draft in
                        try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                            .submitFollowUpUpdate(memberID: memberID, existing: remote, draft: draft)
                    }
                )
            }
        }
    }
}

#Preview("Edit destination — medication — Light") {
    CompatibleNavigationContainer {
        MedicalCaseTimelineEditDestination(
            route: .standaloneMedication(
                SparkMedicalSyncAPI.RemoteMedication(
                    id: 9,
                    member: 1,
                    batch: 3,
                    genericName: "布洛芬",
                    brandName: "",
                    drugName: "布洛芬缓释胶囊",
                    dosageForm: "胶囊",
                    strength: "300mg",
                    route: "口服",
                    dosePerTime: "1 粒",
                    doseValue: 1,
                    doseUnit: "粒",
                    frequencyCode: "BID",
                    period: "日",
                    timesPerPeriod: 2,
                    frequencyText: "每日 2 次",
                    durationDays: 5,
                    instructions: "饭后服",
                    reminderEnabled: false,
                    reminderTimes: [],
                    sortOrder: 0,
                    extra: nil,
                    updatedAt: Date()
                )
            ),
            memberID: 1,
            medicalCaseID: 42,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            eventID: "medication-9",
            onRecordRemoved: { _ in }
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Edit destination — medication — Dark") {
    CompatibleNavigationContainer {
        MedicalCaseTimelineEditDestination(
            route: .standaloneMedication(
                SparkMedicalSyncAPI.RemoteMedication(
                    id: 9,
                    member: 1,
                    batch: 3,
                    genericName: "布洛芬",
                    brandName: "",
                    drugName: "布洛芬缓释胶囊",
                    dosageForm: "胶囊",
                    strength: "300mg",
                    route: "口服",
                    dosePerTime: "1 粒",
                    doseValue: 1,
                    doseUnit: "粒",
                    frequencyCode: "BID",
                    period: "日",
                    timesPerPeriod: 2,
                    frequencyText: "每日 2 次",
                    durationDays: 5,
                    instructions: "饭后服",
                    reminderEnabled: false,
                    reminderTimes: [],
                    sortOrder: 0,
                    extra: nil,
                    updatedAt: Date()
                )
            ),
            memberID: 1,
            medicalCaseID: 42,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            eventID: "medication-9",
            onRecordRemoved: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Edit destination — examination — Light") {
    CompatibleNavigationContainer {
        MedicalCaseTimelineEditDestination(
            route: .examination(
                SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
                    id: 5,
                    member: 1,
                    medicalRecord: 42,
                    category: "laboratory",
                    subCategory: "血常规",
                    itemName: "血常规检查",
                    performedAt: Date(),
                    reportedAt: Date(),
                    organizationName: "仁和医院",
                    departmentName: "检验科",
                    doctorName: "李医生",
                    findings: "白细胞计数正常",
                    impression: "未见明显异常",
                    source: 2,
                    status: 1,
                    extra: nil,
                    createdAt: Date(),
                    updatedAt: Date(),
                    attachments: [],
                    medExamDetails: []
                ),
                category: .laboratory
            ),
            memberID: 1,
            medicalCaseID: 42,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            eventID: "examination-5",
            onRecordRemoved: { _ in }
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Edit destination — symptom — Light") {
    CompatibleNavigationContainer {
        MedicalCaseTimelineEditDestination(
            route: .symptom(
                SparkMedicalSyncAPI.RemoteSymptom(
                    id: 14,
                    member: 1,
                    medicalCase: 42,
                    name: "头痛",
                    code: "R51",
                    severity: "中度",
                    startedAt: Date(),
                    durationValue: 3,
                    durationUnit: "天",
                    bodyPart: "头部",
                    notes: "伴恶心",
                    extra: nil,
                    updatedAt: Date()
                )
            ),
            memberID: 1,
            medicalCaseID: 42,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            eventID: "symptom-14",
            onRecordRemoved: { _ in }
        )
    }
    .preferredColorScheme(.light)
}
