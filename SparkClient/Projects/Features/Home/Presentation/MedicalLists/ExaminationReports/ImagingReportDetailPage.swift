import SwiftUI

/// 影像检查明细页：聚合部位、模态、结果与诊断。
struct ImagingReportDetailPage: View {
    let report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        (report.medExamDetails ?? []).sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        List {
            ForEach(detailItems, id: \.id) { item in
                ImagingDetailCard(item: item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(report.itemName?.nonEmpty ?? L10n.text("home.medical.list.examination.category.imaging"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ImagingDetailCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedExamDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.itemName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if item.flag.isEmpty == false {
                    Text(item.flag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : .secondary)
                }
            }

            detailRow(L10n.text("home.medical.list.examination.card.category"), item.category)
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.modality"), item.modality.nonEmpty ?? "—")
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.body_part"), item.bodyPart.nonEmpty ?? "—")
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.result"), [item.resultValue, item.unit].filter { $0.isEmpty == false }.joined())

            if let diagnosis = item.diagnosis?.nonEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("home.medical.list.examination.detail.imaging.diagnosis"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(diagnosis)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
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
