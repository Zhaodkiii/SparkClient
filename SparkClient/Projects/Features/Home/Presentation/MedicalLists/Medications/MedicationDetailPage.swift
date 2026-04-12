import SwiftUI

/// 用药详情页：独立模块，展示药品基础信息、用法用量与时间信息。
struct MedicationDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteMedication

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var startDateText: String {
        Self.dateFormatter.string(from: item.updatedAt)
    }

    private var endDateText: String? {
        guard let durationDays = item.durationDays, durationDays > 0 else { return nil }
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: item.updatedAt)
        return endDate.map { Self.dateFormatter.string(from: $0) }
    }

    var body: some View {
        List {
            Section("药品信息") {
                metaRow("名称", item.drugName.nonEmpty ?? item.genericName.nonEmpty ?? "")
                metaRow(L10n.text("home.medical.list.medications.specification"), item.strength.nonEmpty ?? "")
                metaRow(L10n.text("home.medical.list.medications.dose_short"), item.dosePerTime.nonEmpty ?? "")
                metaRow(L10n.text("home.medical.list.medications.frequency_title"), item.frequencyText.nonEmpty ?? "")
            }

            if item.instructions.isEmpty == false {
                Section(L10n.text("home.medical.list.medications.instructions_title")) {
                    Text(item.instructions)
                        .font(.body)
                }
            }

            Section(L10n.text("home.medical.list.medications.detail_title")) {
                if item.dosageForm.nonEmpty != nil {
                    metaRow(L10n.text("home.medical.list.medications.form_title"), item.dosageForm)
                }
                if item.route.nonEmpty != nil {
                    metaRow(L10n.text("home.medical.list.medications.route_title"), item.route)
                }
                if let durationDays = item.durationDays {
                    metaRow(L10n.text("home.medical.list.medications.duration_title"), String(format: L10n.text("home.medical.list.medications.duration_value"), durationDays))
                }
                metaRow(L10n.text("home.medical.list.medications.start_date"), startDateText)
                if let endDateText {
                    metaRow(L10n.text("home.medical.list.medications.end_date"), endDateText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.drugName.nonEmpty ?? item.genericName.nonEmpty ?? L10n.text("home.medical.list.medications.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
