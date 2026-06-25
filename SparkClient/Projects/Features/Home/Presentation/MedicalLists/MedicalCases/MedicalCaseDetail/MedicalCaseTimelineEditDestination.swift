import SwiftUI

/// `NavigationLink` 目标：表单 + 删除壳。
struct MedicalCaseTimelineEditDestination: View {
    let route: MedicalCaseTimelineEditRoute
    let memberID: Int
    let medicalCaseID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    var fileTransferService: FileTransferService
    var notificationClient: any NotificationClient
    let eventID: String
    let onRecordRemoved: (String) -> Void

    init(
        route: MedicalCaseTimelineEditRoute,
        memberID: Int,
        medicalCaseID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        eventID: String,
        onRecordRemoved: @escaping (String) -> Void
    ) {
        self.route = route
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.eventID = eventID
        self.onRecordRemoved = onRecordRemoved
    }

    var body: some View {
        switch route {
        case .prescription(let prescription, let plans):
            MedicalTimelineDeleteShell(
                resourceKind: .prescriptions,
                resourceID: prescription.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                MedicationPrescriptionEditPage(
                    prescription: prescription,
                    plans: plans,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onSaved: { _ in },
                    onPlanUnlinked: { _ in }
                )
            }

        case .medicationPlan(let plan, let medicineBoxes):
            MedicalTimelineDeleteShell(
                resourceKind: .medicationPlans,
                resourceID: plan.id,
                workflowAPI: workflowAPI,
                onDeleted: { onRecordRemoved(eventID) }
            ) {
                MedicationPlanFormView(
                    mode: .serverEdit(existing: plan),
                    memberID: memberID,
                    medicineBoxes: medicineBoxes,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onMedicineBoxSaved: { _ in },
                    onServerSaved: { _ in }
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
                    mode: .serverEdit(existing: report),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
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
                    mode: .serverEdit(existing: remote),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID
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
                    mode: .serverEdit(existing: remote),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID
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
                    mode: .serverEdit(existing: remote),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID
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
                    mode: .serverEdit(existing: remote),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID
                )
            }
        }
    }
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
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
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
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
            eventID: "symptom-14",
            onRecordRemoved: { _ in }
        )
    }
    .preferredColorScheme(.light)
}
