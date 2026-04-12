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
                            .submitPrescriptionBatch(memberID: memberID, draft: draft)
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
        }
    }
}

#Preview("Edit destination — medication — Light") {
    NavigationView {
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
    NavigationView {
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
