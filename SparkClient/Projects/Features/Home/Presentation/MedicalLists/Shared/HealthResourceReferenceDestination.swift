import SwiftUI

/// 问报告 / 消息流健康资料引用统一详情路由（按 `resourceType` 分发到 Home 现有详情页或只读兜底页）。
struct HealthResourceReferenceDestination: View {
    let reference: HealthResourceReference
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onCompleteDataPatched: ((SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void)?
    let logger: Logger

    @State private var loadState: HealthResourceReferenceDetailLoadState = .idle
    @State private var examinationReport: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments?

    private var workflowAPI: SparkMedicalWorkflowAPI { medicalQueryAPI.medicalWorkflowAPI }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView(L10n.text("chat.ask_report.detail.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                placeholderState(
                    title: L10n.text("chat.ask_report.message_card.unavailable"),
                    systemImage: "doc.text.magnifyingglass",
                    message: L10n.text("chat.ask_report.detail.not_found_hint")
                )
            case .failed(let message):
                placeholderState(
                    title: L10n.text("chat.ask_report.detail.failed_title"),
                    systemImage: "exclamationmark.triangle",
                    message: message
                )
            case .loaded(let payload):
                detailContent(payload)
            }
        }
        .task(id: reference.cacheKey) {
            await loadDetail()
        }
    }

    @ViewBuilder
    private func detailContent(_ payload: HealthResourceReferenceDetailPayload) -> some View {
        switch payload {
        case .examinationReport(let report):
            ExaminationReportSummaryDetailPage(
                report: examinationReportBinding(initial: report),
                category: ExaminationReportCategory.from(report.category),
                fileTransferService: fileTransferService,
                workflowAPI: workflowAPI,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient
            )
        case .healthExamReport(let item):
            HealthExamReportDetailPage(
                item: item,
                fileTransferService: fileTransferService,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                notificationClient: notificationClient
            )
        case .medicalCase(let item):
            MedicalCaseDetailPage(
                item: item,
                completeData: cachedCompleteData,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient,
                onUpdated: { _ in },
                onDeleted: { _ in }
            )
        case .prescription(let rx, let plans, let boxes, let records):
            MedicationPrescriptionDetailPage(
                prescription: rx,
                plans: plans,
                medicineBoxes: boxes,
                recordsByPlanID: records,
                memberID: reference.memberID,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                onPrescriptionSaved: { _ in },
                onPrescriptionDeleted: { _ in },
                onPlanSaved: { _ in },
                onPlanDeleted: { _ in }
            )
        case .medicationPlan(let plan, let boxes):
            MedicationPlanDetailPage(
                plan: plan,
                medicineBoxes: boxes,
                memberID: reference.memberID,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                onSaved: { _ in },
                onDeleted: { _ in },
                onMedicineBoxSaved: { _ in }
            )
        case .medicineBox(let box, let allBoxes):
            MedicineBoxDetailPage(
                box: box,
                entryMemberID: reference.memberID,
                typeOptions: MedicineBoxTypeCatalog.options(in: allBoxes),
                specOptionBoxes: allBoxes.filter { $0.medicineName == box.medicineName },
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                onSaved: { _ in },
                onDeleted: { _ in }
            )
        case .medicationExecution(let memberID, let plans, let boxes, let records):
            MedicationExecutionCenterPage(
                medicationPlans: plans,
                medicineBoxes: boxes,
                initialRecords: records,
                memberID: memberID,
                medicalQueryAPI: medicalQueryAPI,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                logger: logger
            )
        case .readOnly(let snapshot):
            HealthResourceReadOnlyFallbackPage(snapshot: snapshot)
        }
    }

    private func examinationReportBinding(
        initial: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    ) -> Binding<SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments> {
        Binding(
            get: { examinationReport ?? initial },
            set: { examinationReport = $0 }
        )
    }

    private func placeholderState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadDetail() async {
        loadState = .loading
        let loader = HealthResourceDetailLoader(
            repository: HealthResourceRepository(medicalQueryAPI: medicalQueryAPI),
            logger: logger
        )
        let result = await loader.load(
            reference: reference,
            cachedCompleteData: cachedCompleteData,
            onCompleteDataPatched: onCompleteDataPatched
        )
        if case .loaded(let payload) = result,
           case .examinationReport(let report) = payload {
            examinationReport = report
        }
        loadState = result
    }
}
