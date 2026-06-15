import SwiftUI

/// 首页医疗卡片点击后进入的列表页路由。
enum HomeMedicalListRoute: Hashable {
    case medicalCases
    case healthExamReports
    case examinationReports
    case medicationPlans
}

/// 医疗列表总入口：首屏直接消费 `/complete-data/`，列表内按需刷新对应资源。
struct HomeMedicalListView: View {
    let route: HomeMedicalListRoute
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let dependencies: HomeFeatureDependencies
    let initialFocus: MedicationExecutionInitialFocus?
    let onDismiss: (() -> Void)?
    let onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    let onHealthExamReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?
    let onMedicationPlansUpdated: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)?
    let onPrescriptionsUpdated: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)?
    let onMedicineBoxesUpdated: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?

    init(
        route: HomeMedicalListRoute,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        dependencies: HomeFeatureDependencies,
        initialFocus: MedicationExecutionInitialFocus? = nil,
        onDismiss: (() -> Void)? = nil,
        onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?,
        onHealthExamReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?,
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?,
        onMedicationPlansUpdated: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)?,
        onPrescriptionsUpdated: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)?,
        onMedicineBoxesUpdated: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?
    ) {
        self.route = route
        self.completeData = completeData
        self.dependencies = dependencies
        self.initialFocus = initialFocus
        self.onDismiss = onDismiss
        self.onMedicalCasesUpdated = onMedicalCasesUpdated
        self.onHealthExamReportsUpdated = onHealthExamReportsUpdated
        self.onExaminationReportsUpdated = onExaminationReportsUpdated
        self.onMedicationPlansUpdated = onMedicationPlansUpdated
        self.onPrescriptionsUpdated = onPrescriptionsUpdated
        self.onMedicineBoxesUpdated = onMedicineBoxesUpdated
    }

    var body: some View {
        switch route {
        case .medicalCases:
            MedicalCasesListPage(
                completeData: completeData,
                workflowAPI: dependencies.medicalWorkflowAPI,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
                medicalDocumentUploadViewModel: dependencies.medicalDocumentUploadViewModel,
                aiSettingsViewModel: dependencies.aiSettingsViewModel,
                notificationClient: dependencies.notificationClient,
                logger: dependencies.logger,
                onCasesUpdated: onMedicalCasesUpdated,
                onExaminationReportsUpdated: onExaminationReportsUpdated
            )
        case .healthExamReports:
            HealthExamReportsListPage(
                completeData: completeData,
                workflowAPI: dependencies.medicalWorkflowAPI,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                logger: dependencies.logger,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
                medicalDocumentUploadViewModel: dependencies.medicalDocumentUploadViewModel,
                aiSettingsViewModel: dependencies.aiSettingsViewModel,
                notificationClient: dependencies.notificationClient,
                onReportsUpdated: onHealthExamReportsUpdated
            )
        case .examinationReports:
            ExaminationReportsListPage(
                completeData: completeData,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                logger: dependencies.logger,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
                medicalDocumentUploadViewModel: dependencies.medicalDocumentUploadViewModel,
                aiSettingsViewModel: dependencies.aiSettingsViewModel,
                notificationClient: dependencies.notificationClient,
                onReportsUpdated: onExaminationReportsUpdated,
                onMedicalCasesUpdated: onMedicalCasesUpdated
            )
        case .medicationPlans:
            MedicationExecutionCenterPage(
                medicationPlans: completeData?.medicationPlans ?? [],
                medicineBoxes: completeData?.medicineBoxes ?? [],
                initialRecords: completeData?.todayMedicationRecords ?? [],
                memberID: completeData?.memberId ?? dependencies.memberContextStore.context.selectedMember?.id,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                workflowAPI: dependencies.medicalWorkflowAPI,
                fileTransferService: dependencies.fileTransferService,
                notificationClient: dependencies.notificationClient,
                logger: dependencies.logger,
                completeData: completeData,
                memberContextStore: dependencies.memberContextStore,
                medicalDocumentUploadViewModel: dependencies.medicalDocumentUploadViewModel,
                aiSettingsViewModel: dependencies.aiSettingsViewModel,
                homeDependencies: dependencies,
                initialFocus: initialFocus,
                onMedicationPlansChanged: onMedicationPlansUpdated,
                onPrescriptionsChanged: onPrescriptionsUpdated,
                onMedicineBoxesChanged: onMedicineBoxesUpdated
            )
            .onDisappear {
                onDismiss?()
            }
        }
    }
}

#Preview("Medical Lists Light") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medicalCases, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil, onMedicationPlansUpdated: nil, onPrescriptionsUpdated: nil, onMedicineBoxesUpdated: nil)
    }
    .preferredColorScheme(.light)
}

#Preview("Medical Lists Dark") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medicationPlans, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil, onMedicationPlansUpdated: nil, onPrescriptionsUpdated: nil, onMedicineBoxesUpdated: nil)
    }
    .preferredColorScheme(.dark)
}
