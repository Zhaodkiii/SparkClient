import SwiftUI

/// 处方 / 病例时间轴等处共用的「用药计划」摘要行；可选 `NavigationLink` 进入用药计划详情。
struct PrescriptionMedicationPlanSummaryRow: View {
    struct PlanDetailNavigation {
        var mode: MedicationPlanDetailMode = .server
        var medicationIndex: Int = 0
        var sourcePlanDraft: MedicationPlanRecognitionDraft?
        let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
        let memberID: Int?
        let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
        let memberContextStore: MemberContextStore
        let workflowAPI: SparkMedicalWorkflowAPI
        let notificationClient: any NotificationClient
        var homeDependencies: HomeFeatureDependencies?
        let onPlanSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
        let onPlanDeleted: (Int) -> Void
        let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
        var onMedicineBoxDeleted: ((Int) -> Void)?
        var onLocalDraftPlanSaved: ((MedicationPlanRecognitionDraft) -> Void)?
        var onLocalDraftPlanDeleted: (() -> Void)?
        var onLocalDraftMedicineBoxSaved: ((MedicineBoxRecognitionDraft) -> Void)?
        var onLocalDraftMedicineBoxDeleted: (() -> Void)?
        var onPlanMutation: ((SparkMedicalSyncAPI.MedicationMutationResponse) -> Void)?
    }

    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let fileTransferService: FileTransferService
    var planDetailNavigation: PlanDetailNavigation?

    private var takenCount: Int {
        records.filter { $0.status == "taken" }.count
    }

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        if let boxAttachment = medicineBox?.attachments?.first(where: \.isMedicationImageLike) {
            return boxAttachment
        }
        return plan.attachments?.first(where: \.isMedicationImageLike)
    }

    private var subtitle: String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderEnabled ? plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var stockText: String? {
        guard let medicineBox else { return nil }
        guard let q = medicineBox.totalQuantity else { return "药箱存量未填" }
        return "药箱存量 \(q.formatted(.number.precision(.fractionLength(0...2))))"
    }

    var body: some View {
        Group {
            if let nav = planDetailNavigation {
                MainNavigationLink {
                    MedicationPlanDetailPage(
                        mode: nav.mode,
                        plan: plan,
                        medicineBoxes: nav.medicineBoxes,
                        records: records,
                        memberID: nav.memberID,
                        completeData: nav.completeData,
                        memberContextStore: nav.memberContextStore,
                        workflowAPI: nav.workflowAPI,
                        fileTransferService: fileTransferService,
                        notificationClient: nav.notificationClient,
                        homeDependencies: nav.homeDependencies,
                        sourcePlanDraft: nav.sourcePlanDraft,
                        onSaved: nav.onPlanSaved,
                        onDeleted: nav.onPlanDeleted,
                        onMedicineBoxSaved: nav.onMedicineBoxSaved,
                        onMedicineBoxDeleted: nav.onMedicineBoxDeleted,
                        onLocalDraftSaved: nav.onLocalDraftPlanSaved,
                        onLocalDraftDeleted: nav.onLocalDraftPlanDeleted,
                        onLocalDraftMedicineBoxSaved: nav.onLocalDraftMedicineBoxSaved,
                        onLocalDraftMedicineBoxDeleted: nav.onLocalDraftMedicineBoxDeleted,
                        onMutation: nav.onPlanMutation
                    )
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
            } else {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationImageGlyph(
                seed: plan.id,
                attachment: imageAttachment,
                fileTransferService: fileTransferService
            )
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.drugName.nilIfBlank ?? "未命名药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle.isEmpty ? "暂无补充信息" : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let stockText {
                    Text(stockText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(medicationPlanSummaryStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medicationPlanSummaryStatusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(medicationPlanSummaryStatusColor(plan.status).opacity(0.12), in: Capsule())

                Text("\(takenCount)/\(records.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private func medicationPlanSummaryStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return "执行中"
    case "paused":
        return "未开始"
    case "completed":
        return "已完成"
    case "cancelled":
        return "已取消"
    default:
        return status
    }
}

private func medicationPlanSummaryStatusColor(_ status: String) -> Color {
    switch status {
    case "active":
        return Color(uiColor: .systemBlue)
    case "paused":
        return Color(uiColor: .systemOrange)
    case "completed":
        return Color(uiColor: .systemGreen)
    case "cancelled":
        return Color(uiColor: .systemGray)
    default:
        return Color(uiColor: .secondaryLabel)
    }
}
