import SwiftUI

/// 首页医疗卡片点击后进入的列表页路由。
enum HomeMedicalListRoute: Hashable {
    case medicalCases
    case healthExamReports
    case examinationReports
    case medications
}

/// 医疗列表总入口：直接消费 `/complete-data/`，不额外发起网络请求。
struct HomeMedicalListView: View {
    let route: HomeMedicalListRoute
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let dependencies: HomeFeatureDependencies
    let onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    let onHealthExamReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?
    let onPrescriptionBatchesUpdated: (([SparkMedicalSyncAPI.RemotePrescriptionBatchComplete]) -> Void)?

    var body: some View {
        switch route {
        case .medicalCases:
            MedicalCasesListPage(
                completeData: completeData,
                workflowAPI: dependencies.medicalWorkflowAPI,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
                notificationClient: dependencies.notificationClient,
                onCasesUpdated: onMedicalCasesUpdated
            )
        case .healthExamReports:
            HealthExamReportsListPage(
                completeData: completeData,
                workflowAPI: dependencies.medicalWorkflowAPI,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                logger: dependencies.logger,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
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
                notificationClient: dependencies.notificationClient,
                onReportsUpdated: onExaminationReportsUpdated,
                onMedicalCasesUpdated: onMedicalCasesUpdated
            )
        case .medications:
            MedicationsListPage(
                completeData: completeData,
                fileTransferService: dependencies.fileTransferService,
                workflowAPI: dependencies.medicalWorkflowAPI,
                memberContextStore: dependencies.memberContextStore,
                notificationClient: dependencies.notificationClient,
                onPrescriptionBatchesUpdated: onPrescriptionBatchesUpdated,
                onMedicalCasesUpdated: onMedicalCasesUpdated
            )
        }
    }
}

#Preview("Medical Lists Light") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medicalCases, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil, onPrescriptionBatchesUpdated: nil)
    }
    .preferredColorScheme(.light)
}

#Preview("Medical Lists Dark") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medications, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil, onPrescriptionBatchesUpdated: nil)
    }
    .preferredColorScheme(.dark)
}
