import SwiftUI

/// 病理检查明细页：强调结果与病理诊断。
struct PathologyReportDetailPage: View {
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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(detailItems, id: \.id) { item in
                    PathologyDetailCard(item: item)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(report.itemName?.nonEmpty ?? L10n.text("home.medical.list.examination.category.pathology"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PathologyDetailCard: View {
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

            detailBlock(L10n.text("home.medical.list.examination.card.category"), item.category)
            detailBlock(L10n.text("home.medical.list.examination.card.subcategory"), item.subCategory)
            detailBlock(L10n.text("home.medical.list.examination.detail.pathology.result"), [item.resultValue, item.unit].filter { $0.isEmpty == false }.joined())

            if let diagnosis = item.diagnosis?.nonEmpty {
                detailBlock(L10n.text("home.medical.list.examination.detail.pathology.diagnosis"), diagnosis)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func detailBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
