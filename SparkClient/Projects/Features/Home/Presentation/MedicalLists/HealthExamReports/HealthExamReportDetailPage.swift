import SwiftUI

/// 体检报告详情页入口：复用体检识别结果主页面，以只读模式展示已入库数据。
struct HealthExamReportDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments
    let fileTransferService: FileTransferService
    let memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let notificationClient: any NotificationClient
    var onDeleted: ((Int) -> Void)?
    var onArchiveStateChanged: ((Int, Bool) -> Void)? = nil
    var archiveMode: MedicalArchiveListMode = .active

    private var healthResourceConversationRequest: HealthResourceConversationRequest {
        HealthResourceConversationRequest(
            identity: HealthResourceIdentity(
                type: .healthExamReport,
                resourceID: item.id,
                memberID: item.member
            ),
            displayTitle: item.institutionName.flatMap { $0.nilIfBlank }
                ?? item.reportNo.flatMap { $0.nilIfBlank }
                ?? L10n.text("chat.ask_report.resource_type.health_exam_report", fallback: "体检报告"),
            displaySubtitle: item.summary.flatMap { $0.nilIfBlank } ?? "",
            typeBadge: L10n.text("chat.ask_report.resource_type.health_exam_report", fallback: "体检"),
            source: "health_exam_report_detail"
        )
    }

    var body: some View {
        HealthExamRecognitionResultView(
            item: item,
            fileTransferService: fileTransferService,
            memberContextStore: memberContextStore,
            workflowAPI: workflowAPI,
            notificationClient: notificationClient,
            onDeleted: onDeleted,
            onArchiveStateChanged: onArchiveStateChanged,
            archiveMode: archiveMode
        )
        .healthResourceConversationOverlay(
            healthResourceConversationRequest,
            isEnabled: item.id > 0 && item.member > 0
        )
    }
}
