import SwiftUI

/// 体检报告详情页入口：复用体检识别结果主页面，以只读模式展示已入库数据。
struct HealthExamReportDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments
    let fileTransferService: FileTransferService
    let memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let notificationClient: any NotificationClient
    var onDeleted: ((Int) -> Void)?

    var body: some View {
        HealthExamRecognitionResultView(
            item: item,
            fileTransferService: fileTransferService,
            memberContextStore: memberContextStore,
            workflowAPI: workflowAPI,
            notificationClient: notificationClient,
            onDeleted: onDeleted
        )
    }
}
