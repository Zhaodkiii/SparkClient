import SwiftUI
import UIKit

/// 对齐 HealthClient `TimelineRow`：左侧色环图标 + 竖线 + 右侧强调卡片。
struct MedicalCaseTimelineRow: View {
    let event: MedicalCaseTimelineEvent
    let isLast: Bool
    let memberID: Int
    let medicalCaseID: Int
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    var notificationClient: any NotificationClient
    var onTimelineEventRemoved: ((String) -> Void)?
    var logger: Logger? = nil
    var onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil

    init(
        event: MedicalCaseTimelineEvent,
        isLast: Bool,
        memberID: Int,
        medicalCaseID: Int,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        logger: Logger? = nil,
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil,
        onTimelineEventRemoved: ((String) -> Void)? = nil
    ) {
        self.event = event
        self.isLast = isLast
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.logger = logger
        self.onExaminationReportsUpdated = onExaminationReportsUpdated
        self.onTimelineEventRemoved = onTimelineEventRemoved
    }

    private var shell: MedicalCaseTimelinePalette {
        event.kind.palette
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var dateText: String {
        Self.dateFormatter.string(from: event.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(shell.tint)
                Image(systemName: shell.iconName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    if let badge = event.statusBadgeText, badge.isEmpty == false {
                        MedicalCaseSeverityBadge(
                            text: badge,
                            tint: Color(uiColor: .systemOrange)
                        )
                    }

                    if let route = event.editRoute {
                        MainNavigationLink {
                            MedicalCaseTimelineEditDestination(
                                route: route,
                                memberID: memberID,
                                medicalCaseID: medicalCaseID,
                                workflowAPI: workflowAPI,
                                fileTransferService: fileTransferService,
                                notificationClient: notificationClient,
                                eventID: event.id,
                                onRecordRemoved: { id in
                                    onTimelineEventRemoved?(id)
                                }
                            )
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color(uiColor: .secondarySystemFill))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("home.medical.case_detail.edit"))
                    }
                }

                timelineCard
            }
        }
        .overlay(alignment: .leading) {
            if isLast == false {
                let centerX: CGFloat = 20
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1)
                    .offset(x: centerX)
                    .padding(.top, 52)
            }
        }
    }

    private var timelineCard: some View {
        Group {
            if hasDetailDestination {
                MainNavigationLink {
                    timelineDetailDestination
                } label: {
                    timelineCardContent
                }
                .buttonStyle(.plain)
            } else {
                timelineCardContent
            }
        }
    }

    private var hasDetailDestination: Bool {
        switch event.kind {
        case .prescription:
            return event.prescription != nil
        case .medication:
            return event.medicationPlan != nil
        case .examination:
            return event.examination != nil
        default:
            return false
        }
    }

    @ViewBuilder
    private var timelineDetailDestination: some View {
        switch event.kind {
        case .prescription:
            if let prescription = event.prescription {
                MedicationPrescriptionDetailPage(
                    prescription: prescription,
                    plans: event.nestedMedicationPlans,
                    medicineBoxes: medicineBoxes,
                    recordsByPlanID: recordsByPlanID,
                    memberID: memberID,
                    completeData: completeData,
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onPrescriptionSaved: { _ in },
                    onPrescriptionDeleted: { _ in onTimelineEventRemoved?(event.id) },
                    onPlanSaved: { _ in },
                    onPlanDeleted: { id in onTimelineEventRemoved?("medication-plan-\(id)") }
                )
            }
        case .medication:
            if let plan = event.medicationPlan {
                MedicationPlanDetailPage(
                    plan: plan,
                    medicineBoxes: medicineBoxes,
                    memberID: memberID,
                    completeData: completeData,
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onSaved: { _ in },
                    onDeleted: { _ in onTimelineEventRemoved?(event.id) },
                    onMedicineBoxSaved: { _ in }
                )
            }
        case .examination(let category):
            if let examination = event.examination {
                MedicalCaseTimelineExaminationDetailHost(
                    report: examination,
                    category: category,
                    medicalQueryAPI: SparkMedicalQueryAPI(configuration: workflowAPI.configuration),
                    completeData: completeData,
                    fileTransferService: fileTransferService,
                    workflowAPI: workflowAPI,
                    memberContextStore: memberContextStore,
                    notificationClient: notificationClient,
                    logger: logger,
                    onExaminationReportsUpdated: onExaminationReportsUpdated
                )
            }
        default:
            EmptyView()
        }
    }

    private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        completeData?.medicineBoxes ?? Array(event.medicineBoxesByID.values)
    }

    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: completeData?.todayMedicationRecords ?? [], by: \.plan)
    }

    private func medicationPlanSummaryRow(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        onPlanDeletedFromDetail: @escaping (Int) -> Void
    ) -> some View {
        PrescriptionMedicationPlanSummaryRow(
            plan: plan,
            medicineBox: plan.medicineBox.flatMap { event.medicineBoxesByID[$0] },
            records: recordsByPlanID[plan.id] ?? [],
            fileTransferService: fileTransferService,
            planDetailNavigation: PrescriptionMedicationPlanSummaryRow.PlanDetailNavigation(
                medicineBoxes: medicineBoxes,
                memberID: memberID,
                completeData: completeData,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                notificationClient: notificationClient,
                onPlanSaved: { _ in },
                onPlanDeleted: onPlanDeletedFromDetail,
                onMedicineBoxSaved: { _ in },
                onMedicineBoxDeleted: nil
            )
        )
    }

    private var timelineCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if event.kind == .prescription, let prescription = event.prescription {
                prescriptionBody(prescription: prescription, plans: event.nestedMedicationPlans)
            } else if event.kind == .medication, let plan = event.medicationPlan {
                medicationPlanBody(plan: plan)
            } else if case .examination(let category) = event.kind, let examination = event.examination {
                examinationBody(examination: examination, category: category)
            } else if event.kind == .visit, let visit = event.visit {
                visitCardBody(visit: visit, detail: event.detail)
            } else if event.kind == .surgery, let surgery = event.surgery {
                surgeryCardBody(surgery: surgery, detail: event.detail)
            } else if event.kind == .followUp, let followUp = event.followUp {
                followUpCardBody(followUp: followUp, detail: event.detail)
            } else if event.kind == .symptom, let symptom = event.symptom {
                symptomCardBody(symptom: symptom, detail: event.detail)
            } else {
                if event.detail.isEmpty == false {
                    Text(event.detail)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(shell.border, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(shell.tint, lineWidth: 3)
                        .mask(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(lineWidth: 3)
                                .padding(.leading, -200)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                        .opacity(0.9)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func prescriptionBody(
        prescription: SparkMedicalSyncAPI.RemotePrescription,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if prescription.diagnosis.nilIfBlank != nil {
                Text(prescription.diagnosis)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let no = prescription.prescriptionNo?.nilIfBlank {
                    MedicalCaseSeverityBadge(text: no, tint: Color(uiColor: .systemPurple))
                }
                if prescription.status.isEmpty == false {
                    MedicalCaseSeverityBadge(text: prescriptionStatusText(prescription.status), tint: Color(uiColor: .systemPurple))
                }
            }

            if plans.isEmpty == false {
                Text("服药计划 \(plans.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(plans, id: \.id) { plan in
                        medicationPlanSummaryRow(plan: plan) { id in
                            onTimelineEventRemoved?("medication-plan-\(id)")
                        }
                    }
                }
            }
        }
    }

    private func medicationPlanBody(plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            medicationPlanSummaryRow(plan: plan) { _ in
                onTimelineEventRemoved?(event.id)
            }

            if plan.instructions.nilIfBlank != nil {
                Text(plan.instructions)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func examinationBody(
        examination: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        category: ExaminationReportCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(category.color)
                Text(L10n.text(category.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(category.color)
            }

            if let org = examination.organizationName?.nonEmpty {
                Text(org)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if (examination.detailText).isEmpty == false {
                Text(examination.detailText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let attachments = examination.attachments, attachments.isEmpty == false {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments, id: \.id) { attachment in
                            MedicalCaseAttachmentPill(
                                attachment: attachment,
                                fileTransferService: fileTransferService
                            )
                        }
                    }
                }
            }
        }
    }

    private func visitCardBody(visit: SparkMedicalSyncAPI.RemoteVisit, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if visit.visitType.nilIfBlank != nil {
                Text(visit.visitType)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if detail.isEmpty == false {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func surgeryCardBody(surgery: SparkMedicalSyncAPI.RemoteSurgery, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if surgery.procedureCode.nilIfBlank != nil {
                Text(surgery.procedureCode)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if detail.isEmpty == false {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func followUpCardBody(followUp: SparkMedicalSyncAPI.RemoteFollowUp, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if followUp.status.nilIfBlank != nil {
                Text(followUp.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if detail.isEmpty == false {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func symptomCardBody(symptom: SparkMedicalSyncAPI.RemoteSymptom, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if symptom.code.nilIfBlank != nil {
                Text(symptom.code)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if detail.isEmpty == false {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prescriptionStatusText(_ status: String) -> String {
        switch status {
        case "active":
            return "生效中"
        case "completed":
            return "已完成"
        case "cancelled":
            return "已取消"
        default:
            return status
        }
    }
}

/// 病例时间轴进入检查详情：`complete-data` 摘要可能未带 `medExamDetails`；与列表页懒加载一致，仅在 `nil` 时请求并回写首页检查报告缓存。
struct MedicalCaseTimelineExaminationDetailHost: View {
    let initialReport: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let category: ExaminationReportCategory
    let medicalQueryAPI: SparkMedicalQueryAPI
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let fileTransferService: FileTransferService
    let workflowAPI: SparkMedicalWorkflowAPI
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let logger: Logger?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?

    @State private var report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    @State private var isLoadingDetails = false

    init(
        report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        category: ExaminationReportCategory,
        medicalQueryAPI: SparkMedicalQueryAPI,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        fileTransferService: FileTransferService,
        workflowAPI: SparkMedicalWorkflowAPI,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        logger: Logger?,
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?
    ) {
        self.initialReport = report
        self.category = category
        self.medicalQueryAPI = medicalQueryAPI
        self.completeData = completeData
        self.fileTransferService = fileTransferService
        self.workflowAPI = workflowAPI
        _memberContextStore = ObservedObject(wrappedValue: memberContextStore)
        self.notificationClient = notificationClient
        self.logger = logger
        self.onExaminationReportsUpdated = onExaminationReportsUpdated
        _report = State(initialValue: report)
    }

    var body: some View {
        detailContent
            .overlay {
                if isLoadingDetails {
                    ZStack {
                        Color(uiColor: .systemGroupedBackground).opacity(0.35)
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(L10n.text("home.medical.list.details.loading"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task(id: initialReport.id) {
                await loadDetailsIfNeeded()
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        ExaminationReportSummaryDetailPage(
            report: $report,
            category: category,
            fileTransferService: fileTransferService,
            workflowAPI: workflowAPI,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: notificationClient,
            onMedicalCaseLinked: { merged in
                patchCompleteDataCacheIfPossible(merged: merged)
            },
            onMedicalCaseUpdated: nil,
            onMedicalCaseDeleted: nil
        )
    }

    private func loadDetailsIfNeeded() async {
        guard report.medExamDetails == nil else { return }
        guard isLoadingDetails == false else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        let memberID = report.member
        let reportID = report.id
        logger?.info(
            "病例时间轴检查明细加载开始 reportID=\(reportID) memberID=\(memberID)",
            module: LogModule.home
        )

        do {
            let rows = try await medicalQueryAPI.listMedExamDetails(
                memberID: memberID,
                businessType: report.medExamDetailBusinessType,
                businessID: reportID
            )
            let filtered = Self.filterMedExamRows(rows)
            var merged = report
            merged.medExamDetails = filtered
            await MainActor.run {
                report = merged
                patchCompleteDataCacheIfPossible(merged: merged)
            }
            logger?.info(
                "病例时间轴检查明细加载完成 reportID=\(reportID) count=\(filtered.count)",
                module: LogModule.home
            )
        } catch {
            logger?.warning(
                "病例时间轴检查明细加载失败 reportID=\(reportID) error=\(error.localizedDescription)",
                module: LogModule.home
            )
        }
    }

    private func patchCompleteDataCacheIfPossible(merged: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) {
        guard let onExaminationReportsUpdated else { return }
        var list = completeData?.examinationReports ?? []
        if let idx = list.firstIndex(where: { $0.id == merged.id }) {
            list[idx] = merged
        } else {
            list.insert(merged, at: 0)
        }
        onExaminationReportsUpdated(list)
    }

    private static func filterMedExamRows(
        _ rows: [SparkMedicalSyncAPI.RemoteMedExamDetail]
    ) -> [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        let accepted = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments.acceptedBusinessTypes
            .map { $0.lowercased() }
        let filtered = rows.filter { row in
            let normalized = row.businessType.lowercased()
            return accepted.contains(normalized) || rows.count == 1
        }
        return filtered.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

private extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
    var detailText: String {
        impression?.nonEmpty ?? findings?.nonEmpty ?? ""
    }
}

#Preview("Timeline row — Light") {
    let event = MedicalCaseTimelineEvent(
        id: "1",
        kind: .symptom,
        title: "头痛",
        detail: "持续 3 天，伴发热",
        date: Date(),
        statusBadgeText: "治疗中"
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: false,
        memberID: 1,
        medicalCaseID: 1,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — Dark") {
    let event = MedicalCaseTimelineEvent(
        id: "1",
        kind: .symptom,
        title: "头痛",
        detail: "持续 3 天，伴发热",
        date: Date(),
        statusBadgeText: "治疗中"
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: false,
        memberID: 1,
        medicalCaseID: 1,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Timeline row — examination laboratory — Light") {
    let report = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
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
        findings: "白细胞计数正常，红细胞计数正常",
        impression: "未见明显异常",
        source: 2,
        status: 1,
        extra: nil,
        createdAt: Date(),
        updatedAt: Date(),
        attachments: [],
        medExamDetails: []
    )
    let event = MedicalCaseTimelineEvent(
        id: "examination-5",
        kind: .examination(.laboratory),
        title: report.itemName ?? "",
        detail: report.impression ?? "",
        date: Date(),
        statusBadgeText: nil,
        examination: report,
        examinationCategory: .laboratory,
        editRoute: .examination(report, category: .laboratory)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — examination imaging — Light") {
    let report = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
        id: 6,
        member: 1,
        medicalRecord: 42,
        category: "imaging",
        subCategory: "胸部CT",
        itemName: "胸部CT平扫",
        performedAt: Date(),
        reportedAt: Date(),
        organizationName: "仁和医院",
        departmentName: "放射科",
        doctorName: "张医生",
        findings: "双肺纹理清晰，未见明显异常密度影",
        impression: "胸部CT未见明显异常",
        source: 2,
        status: 1,
        extra: nil,
        createdAt: Date(),
        updatedAt: Date(),
        attachments: [],
        medExamDetails: []
    )
    let event = MedicalCaseTimelineEvent(
        id: "examination-6",
        kind: .examination(.imaging),
        title: report.itemName ?? "",
        detail: report.impression ?? "",
        date: Date(),
        statusBadgeText: nil,
        examination: report,
        examinationCategory: .imaging,
        editRoute: .examination(report, category: .imaging)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — examination pathology — Dark") {
    let report = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
        id: 7,
        member: 1,
        medicalRecord: 42,
        category: "pathology",
        subCategory: "活检",
        itemName: "胃镜活检病理",
        performedAt: Date(),
        reportedAt: Date(),
        organizationName: "仁和医院",
        departmentName: "病理科",
        doctorName: "陈医生",
        findings: "镜下见部分腺体轻度异型增生",
        impression: "慢性萎缩性胃炎伴轻度异型增生",
        source: 2,
        status: 1,
        extra: nil,
        createdAt: Date(),
        updatedAt: Date(),
        attachments: [],
        medExamDetails: []
    )
    let event = MedicalCaseTimelineEvent(
        id: "examination-7",
        kind: .examination(.pathology),
        title: report.itemName ?? "",
        detail: report.impression ?? "",
        date: Date(),
        statusBadgeText: nil,
        examination: report,
        examinationCategory: .pathology,
        editRoute: .examination(report, category: .pathology)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Timeline row — visit — Light") {
    let visit = SparkMedicalSyncAPI.RemoteVisit(
        id: 11,
        member: 1,
        medicalCase: 42,
        visitType: "outpatient",
        visitedAt: Date(),
        department: "内科",
        doctorName: "王医生",
        visitNo: "OP-9001",
        sourceSystemId: "",
        notes: "复查",
        extra: nil,
        updatedAt: Date()
    )
    let event = MedicalCaseTimelineEvent(
        id: "visit-11",
        kind: .visit,
        title: visit.department,
        detail: "王医生 · OP-9001 · 复查",
        date: Date(),
        statusBadgeText: nil,
        visit: visit,
        editRoute: .visit(visit)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — surgery — Dark") {
    let surgery = SparkMedicalSyncAPI.RemoteSurgery(
        id: 12,
        member: 1,
        medicalCase: 42,
        procedureName: "阑尾切除术",
        procedureCode: "APP",
        site: "右下腹",
        performedAt: Date(),
        surgeon: "李医生",
        anesthesiaType: "全麻",
        incisionLevel: "II",
        asaClass: "II",
        sourceSystemId: "",
        notes: "顺利",
        extra: nil,
        updatedAt: Date()
    )
    let event = MedicalCaseTimelineEvent(
        id: "surgery-12",
        kind: .surgery,
        title: surgery.procedureName,
        detail: "李医生 · 右下腹 · 顺利",
        date: Date(),
        statusBadgeText: nil,
        surgery: surgery,
        editRoute: .surgery(surgery)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Timeline row — follow-up — Light") {
    let followUp = SparkMedicalSyncAPI.RemoteFollowUp(
        id: 13,
        member: 1,
        medicalCase: 42,
        plannedAt: Date(),
        completedAt: Date(),
        status: "done",
        method: "phone",
        outcome: "症状缓解",
        nextAction: "三月后复诊",
        extra: nil,
        updatedAt: Date()
    )
    let event = MedicalCaseTimelineEvent(
        id: "follow-up-13",
        kind: .followUp,
        title: followUp.method,
        detail: "症状缓解 · 三月后复诊",
        date: Date(),
        statusBadgeText: nil,
        followUp: followUp,
        editRoute: .followUp(followUp)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — symptom structured — Dark") {
    let symptom = SparkMedicalSyncAPI.RemoteSymptom(
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
    let event = MedicalCaseTimelineEvent(
        id: "symptom-14",
        kind: .symptom,
        title: symptom.name,
        detail: "中度 · 头部 · 伴恶心",
        date: Date(),
        statusBadgeText: nil,
        symptom: symptom,
        editRoute: .symptom(symptom)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        completeData: nil,
        memberContextStore: AppContainer.preview.memberContextStore,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        notificationClient: AppContainer.preview.notificationClient,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}
