import SwiftUI

enum MedicalMedicationListItem: Identifiable {
    case prescription(id: Int, prescription: SparkMedicalSyncAPI.RemotePrescription?, plans: [SparkMedicalSyncAPI.RemoteMedicationPlan])
    case standalonePlan(SparkMedicalSyncAPI.RemoteMedicationPlan)

    var id: String {
        switch self {
        case .prescription(let id, _, _):
            return "prescription_\(id)"
        case .standalonePlan(let plan):
            return "plan_\(plan.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .prescription(_, let prescription, let plans):
            return prescription?.prescribedAt
                ?? plans.map(\.startDate).max()
                ?? prescription?.updatedAt
                ?? .distantPast
        case .standalonePlan(let plan):
            return plan.startDate
        }
    }

    var plans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        switch self {
        case .prescription(_, _, let plans):
            return plans
        case .standalonePlan(let plan):
            return [plan]
        }
    }
}

enum MedicalMedicationListBuilder {
    static func sortedItems(
        medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        prescriptions: [SparkMedicalSyncAPI.RemotePrescription]
    ) -> [MedicalMedicationListItem] {
        let sortedPlans = medicationPlans.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.startDate > rhs.startDate
            }
            return statusRank(lhs.status) < statusRank(rhs.status)
        }

        let linkedPlans = sortedPlans.filter { $0.prescription != nil }
        let plansByPrescriptionID = Dictionary(grouping: linkedPlans) { plan in
            plan.prescription ?? 0
        }
        let prescriptionsByID = Dictionary(uniqueKeysWithValues: prescriptions.map { ($0.id, $0) })

        var items: [MedicalMedicationListItem] = []
        let prescriptionIDs = Set(prescriptions.map(\.id)).union(plansByPrescriptionID.keys)

        for prescriptionID in prescriptionIDs {
            let plans = plansByPrescriptionID[prescriptionID] ?? []
            if prescriptionsByID[prescriptionID] != nil || plans.isEmpty == false {
                items.append(.prescription(id: prescriptionID, prescription: prescriptionsByID[prescriptionID], plans: plans))
            }
        }

        for plan in sortedPlans where plan.prescription == nil {
            items.append(.standalonePlan(plan))
        }

        return items.sorted { $0.sortDate > $1.sortDate }
    }

    static func statusRank(_ status: String) -> Int {
        switch status {
        case "active":
            return 0
        case "paused":
            return 1
        case "completed":
            return 2
        case "cancelled":
            return 3
        default:
            return 4
        }
    }
}

enum MedicationPlanSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicationPlan)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let plan):
            return "server_\(plan.id)"
        }
    }

    var planMode: MedicationPlanStepperView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let plan):
            return .serverEdit(existing: plan)
        }
    }

    var formMode: MedicationPlanFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let plan):
            return .serverEdit(existing: plan)
        }
    }
}

struct MedicationPrescriptionCard<Destination: View>: View {
    let prescription: SparkMedicalSyncAPI.RemotePrescription?
    let plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    let recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    let fileTransferService: FileTransferService
    @ViewBuilder let planDestination: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Destination

    private var title: String {
        prescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.list.medications.prescription_batch", fallback: "处方批次")
    }

    private var subtitleItems: [String] {
        [
            prescription?.prescriberName.nilIfBlank.map {
                String(format: L10n.text("home.medical.list.medications.prescriber_format", fallback: "医生：%@"), locale: .current, $0)
            },
            prescription?.prescriptionNo?.nilIfBlank.map {
                String(format: L10n.text("home.medical.list.medications.prescription_no_format", fallback: "处方号：%@"), locale: .current, $0)
            },
            prescriptionDateText
        ].compactMap { $0 }
    }

    private var prescriptionDateText: String? {
        guard let date = prescription?.prescribedAt else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let diagnosis = prescription?.diagnosis.nilIfBlank {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("common.diagnosis"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                    Text(diagnosis)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(uiColor: .systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .systemBlue).opacity(0.18), lineWidth: 1)
                )
            }

            Divider()

            HStack(spacing: 8) {
                Text(String(format: L10n.text("home.medical.list.medications.plan_count_format", fallback: "用药（%d种）"), locale: .current, plans.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = prescription?.status.nilIfBlank {
                    Text(medicalPrescriptionStatusText(status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemPurple))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemPurple).opacity(0.12), in: Capsule())
                }
            }

            if plans.isEmpty {
                Text(L10n.text("home.medical.list.medications.empty.linked_plans", fallback: "暂无关联用药计划"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(plans, id: \.id) { plan in
                        MainNavigationLink {
                            planDestination(plan)
                        } label: {
                            MedicationPrescriptionPlanRow(
                                plan: plan,
                                medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                                records: recordsByPlanID[plan.id] ?? [],
                                fileTransferService: fileTransferService
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .systemPurple).opacity(0.14), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemPurple), Color(uiColor: .systemIndigo)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "building.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if subtitleItems.isEmpty == false {
                    Text(subtitleItems.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
    }
}

struct MedicationPrescriptionPlanRow: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let fileTransferService: FileTransferService

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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationImageGlyph(
                seed: plan.id,
                attachment: imageAttachment,
                fileTransferService: fileTransferService
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.drugName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle.isEmpty ? L10n.text("home.medical.prescription.no_supplemental_info", fallback: "暂无补充信息") : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(planStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medicalPlanStatusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(medicalPlanStatusColor(plan.status).opacity(0.12), in: Capsule())

                HStack(spacing: 4) {
                    Image(systemName: plan.reminderEnabled ? "bell.fill" : "bell.slash")
                    Text("\(takenCount)/\(records.count)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MedicationPlanCard: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let fileTransferService: FileTransferService

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
            plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MedicationImageGlyph(
                    seed: plan.id,
                    attachment: imageAttachment,
                    fileTransferService: fileTransferService
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.drugName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle.isEmpty ? L10n.text("home.medical.prescription.no_supplemental_info", fallback: "暂无补充信息") : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(planStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medicalPlanStatusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(medicalPlanStatusColor(plan.status).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                Label("\(takenCount)/\(records.count)", systemImage: "checkmark.circle")
                if let medicineBox {
                    Label(stockText(medicineBox), systemImage: "shippingbox")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func medicalPrescriptionStatusText(_ status: String) -> String {
    if PrescriptionLifecycleStatus.allRawValues.contains(status) {
        return PrescriptionLifecycleStatus.displayLabel(for: status)
    }
    return status
}

func medicalPlanStatusColor(_ status: String) -> Color {
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
