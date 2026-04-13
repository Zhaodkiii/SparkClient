import SwiftUI

struct CaseExamReportsSectionView: View {
    let reports: [MedicalReportRecognitionDraft]
    let onEdit: (Int, MedicalReportRecognitionDraft) -> Void

    var body: some View {
        CaseSectionCard(
            title: "医疗检查报告",
            subtitle: "实验室 / 影像 / 病理聚合展示",
            systemImage: "cross.case",
            badgeText: "\(reports.count)份"
        ) {
            if reports.isEmpty {
                Text("暂无检查报告")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    categoryGroup(title: "实验室", key: "laboratory")
                    categoryGroup(title: "影像", key: "imaging")
                    categoryGroup(title: "病理", key: "pathology")
                }
            }
        }
    }

    private func categoryGroup(title: String, key: String) -> some View {
        let indexed = reports.enumerated().filter { normalizedCategory($0.element.category) == key }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("\(indexed.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }

            if indexed.isEmpty {
                Text("暂无数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            } else {
                ForEach(indexed, id: \.offset) { pair in
                    reportCard(index: pair.offset, report: pair.element)
                }
            }
        }
    }

    private func reportCard(index: Int, report: MedicalReportRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(report.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑") {
                    onEdit(index, report)
                }
                .font(.subheadline.weight(.semibold))
            }

            let subline = [report.hospital, report.doctor, report.date]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            if subline.isEmpty == false {
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(report.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if report.details.isEmpty == false {
                Text("明细 \(report.details.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func normalizedCategory(_ input: String?) -> String {
        let raw = (input ?? "").lowercased()
        if raw.contains("lab") || raw.contains("labor") || raw.contains("检验") {
            return "laboratory"
        }
        if raw.contains("image") || raw.contains("影") || raw.contains("ct") || raw.contains("mri") {
            return "imaging"
        }
        if raw.contains("path") || raw.contains("病理") {
            return "pathology"
        }
        return raw.isEmpty ? "laboratory" : raw
    }
}
