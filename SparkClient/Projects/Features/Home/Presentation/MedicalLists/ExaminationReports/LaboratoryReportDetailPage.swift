import SwiftUI

/// 实验室检查明细页：参考 `LabPanelView` 的表格式阅读体验。
struct LaboratoryReportDetailPage: View {
    let report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    var navigationTitleOverride: String? = nil

    private var resolvedNavigationTitle: String {
        navigationTitleOverride?.nonEmpty
            ?? report.itemName?.nonEmpty
            ?? L10n.text("home.medical.list.examination_reports.title")
    }

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        (report.medExamDetails ?? []).sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(spacing: 0) {
                LaboratoryDetailHeaderRow()
                    .background(.ultraThinMaterial)
                    .overlay(Divider(), alignment: .bottom)

                ForEach(detailItems, id: \.id) { item in
                    LaboratoryDetailRow(item: item)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(resolvedNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LaboratoryDetailHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            headerCell(L10n.text("home.medical.list.examination.detail.lab.item"), width: 180, alignment: .leading)
            headerCell(L10n.text("common.result"), width: 140)
            headerCell(L10n.text("home.medical.list.examination.detail.lab.reference"), width: 150)
            headerCell(L10n.text("common.status"), width: 120)
        }
        .padding(.vertical, 10)
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 12)
    }
}

private struct LaboratoryDetailRow: View {
    let item: SparkMedicalSyncAPI.RemoteMedExamDetail

    private var flagColor: Color {
        item.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : Color(uiColor: .systemGreen)
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(width: 180, alignment: .leading) {
                Text(item.itemName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            cell(width: 140) {
                HStack(spacing: 2) {
                    Text(item.resultValue ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if item.unit.isEmpty == false {
                        Text(item.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            cell(width: 150) {
                Text(item.referenceRange.nonEmpty ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            cell(width: 120) {
                Text(item.flag.nonEmpty ?? L10n.text("common.normal"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(flagColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(flagColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private func cell<Content: View>(width: CGFloat, alignment: Alignment = .center, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 12)
    }
}
