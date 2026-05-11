import SwiftUI

/// 首页医疗卡片点击后进入的列表页路由。
enum HomeMedicalListRoute: Hashable {
    case medicalCases
    case healthExamReports
    case examinationReports
    case medicationPlans
}

/// 医疗列表总入口：直接消费 `/complete-data/`，不额外发起网络请求。
struct HomeMedicalListView: View {
    let route: HomeMedicalListRoute
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let dependencies: HomeFeatureDependencies
    let onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    let onHealthExamReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?

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
        case .medicationPlans:
            MedicationsListPage(
                completeData: completeData,
                workflowAPI: dependencies.medicalWorkflowAPI,
                fileTransferService: dependencies.fileTransferService,
                memberContextStore: dependencies.memberContextStore,
                medicalDocumentUploadViewModel: dependencies.medicalDocumentUploadViewModel,
                notificationClient: dependencies.notificationClient
            )
        }
    }
}

#Preview("Medical Lists Light") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medicalCases, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil)
    }
    .preferredColorScheme(.light)
}

#Preview("Medical Lists Dark") {
    CompatibleNavigationContainer {
        HomeMedicalListView(route: .medicationPlans, completeData: nil, dependencies: .preview, onMedicalCasesUpdated: nil, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil)
    }
    .preferredColorScheme(.dark)
}
