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
    let appContainer: AppContainer
    let onHealthExamReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?

    var body: some View {
        switch route {
        case .medicalCases:
            MedicalCasesListPage(
                completeData: completeData,
                fileTransferService: appContainer.fileTransferService
            )
        case .healthExamReports:
            HealthExamReportsListPage(
                completeData: completeData,
                medicalQueryAPI: appContainer.backend.medicalQuery,
                logger: appContainer.logger,
                fileTransferService: appContainer.fileTransferService,
                onReportsUpdated: onHealthExamReportsUpdated
            )
        case .examinationReports:
            ExaminationReportsListPage(
                completeData: completeData,
                medicalQueryAPI: appContainer.backend.medicalQuery,
                logger: appContainer.logger,
                fileTransferService: appContainer.fileTransferService,
                onReportsUpdated: onExaminationReportsUpdated
            )
        case .medications:
            MedicationsListPage(
                completeData: completeData,
                fileTransferService: appContainer.fileTransferService
            )
        }
    }
}

#Preview("Medical Lists Light") {
    NavigationView {
        HomeMedicalListView(route: .medicalCases, completeData: nil, appContainer: .preview, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil)
    }
    .preferredColorScheme(.light)
}

#Preview("Medical Lists Dark") {
    NavigationView {
        HomeMedicalListView(route: .medications, completeData: nil, appContainer: .preview, onHealthExamReportsUpdated: nil, onExaminationReportsUpdated: nil)
    }
    .preferredColorScheme(.dark)
}
