import SwiftUI
import UIKit

struct HealthExamMemberSectionView: View {
    let memberID: Int?
    let draft: HealthExamRecognitionDraft

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.total_count"),
                    value: "\(draft.items.count)"
                )
            }
        }
    }
}

struct HealthExamBasicInfoSectionView: View {
    let draft: HealthExamRecognitionDraft
    let onEdit: () -> Void

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.health_exam.basic_info.title"),
            subtitle: L10n.text("medical.upload.result.health_exam.basic_info.subtitle"),
            systemImage: "doc.text",
            actionTitle: L10n.text("medical.upload.result.common.edit"),
            action: onEdit
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.basic_info.institution"),
                    value: draft.institutionName ?? ""
                )
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.basic_info.report_no"),
                    value: draft.reportNo ?? ""
                )
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.basic_info.exam_date"),
                    value: draft.examDate ?? ""
                )
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.basic_info.exam_type"),
                    value: draft.examType ?? ""
                )
                HealthExamResultInfoLine(
                    title: L10n.text("medical.upload.result.health_exam.basic_info.summary"),
                    value: draft.summary ?? ""
                )
            }
        }
    }
}

struct HealthExamRiskOverviewCard: View {
    let highCount: Int
    let midCount: Int
    let lowCount: Int

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.health_exam.overview.title"),
            subtitle: L10n.text("medical.upload.result.health_exam.overview.subtitle"),
            systemImage: "exclamationmark.triangle"
        ) {
            HStack(spacing: 10) {
                tile(level: .high, count: highCount)
                tile(level: .mid, count: midCount)
                tile(level: .low, count: lowCount)
            }
        }
    }

    private func tile(level: HealthExamRiskLevel, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(level.titleKey))
                .font(.caption)
                .foregroundStyle(level.tint)
            Text("\(count)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(level.tint.opacity(0.10))
        )
    }
}

struct HealthExamSummaryRow: View {
    let totalCount: Int
    let normalCount: Int
    let abnormalCount: Int
    let selectedFilter: HealthExamResultSummaryFilter
    let onSelect: (HealthExamResultSummaryFilter) -> Void

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.health_exam.summary.title"),
            subtitle: L10n.text("medical.upload.result.health_exam.summary.subtitle"),
            systemImage: "sum"
        ) {
            HStack(spacing: 8) {
                summaryButton(.all, value: totalCount)
                summaryButton(.normal, value: normalCount)
                summaryButton(.abnormal, value: abnormalCount)
            }
        }
    }

    private func summaryButton(_ filter: HealthExamResultSummaryFilter, value: Int) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onSelect(filter)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(filter.titleKey))
                    .font(.caption)
                    .foregroundStyle(selectedFilter == filter ? .primary : .secondary)
                Text("\(value)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedFilter == filter ? Color(uiColor: .tertiarySystemGroupedBackground) : Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct HealthExamCategoryGroupsSectionView: View {
    let groups: [(category: String, rows: [HealthExamRiskDisplayItem])]
    let onEditItem: (HealthExamRiskDisplayItem) -> Void
    @Binding var expandedCategories: Set<String>

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.health_exam.groups.title"),
            subtitle: L10n.text("medical.upload.result.health_exam.groups.subtitle"),
            systemImage: "list.bullet.rectangle"
        ) {
            VStack(spacing: 10) {
                ForEach(groups, id: \.category) { group in
                    collapsibleCategoryCard(group)
                }
            }
        }
    }

    private func collapsibleCategoryCard(_ group: (category: String, rows: [HealthExamRiskDisplayItem])) -> some View {
        let expanded = expandedCategories.contains(group.category)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if expanded {
                        expandedCategories.remove(group.category)
                    } else {
                        expandedCategories.insert(group.category)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(group.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(group.rows.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    ForEach(group.rows) { row in
                        HealthExamRiskItemCell(item: row, onEdit: {
                            onEditItem(row)
                        })
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct HealthExamRiskItemCell: View {
    let item: HealthExamRiskDisplayItem
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.item.itemName ?? L10n.text("medical.upload.result.health_exam.item.unnamed"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                let detail = [item.item.resultValue, item.item.unit, item.item.referenceRange]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: " · ")
                if detail.isEmpty == false {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(L10n.text(item.riskLevel.titleKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.riskLevel.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.riskLevel.tint.opacity(0.12))
                )

            Button(L10n.text("medical.upload.result.common.edit"), action: onEdit)
                .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }
}

struct HealthExamAttachmentsSectionView: View {
    let attachments: [HealthExamResultLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    var body: some View {
        HealthExamResultSectionCard(
            title: L10n.text("medical.upload.result.attachments.title"),
            subtitle: L10n.text("medical.upload.result.attachments.subtitle"),
            systemImage: "paperclip",
            badgeText: String(
                format: L10n.text("medical.upload.result.attachments.count"),
                locale: .current,
                attachments.count
            )
        ) {
            if attachments.isEmpty {
                Text(L10n.text("medical.upload.result.attachments.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(attachments) { item in
                        Button {
                            selectedPreview = item.previewInput
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .unifiedFilePreview(selection: $selectedPreview)
    }

    private func row(_ item: HealthExamResultLocalAttachmentItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 40, height: 40)
                Image(systemName: item.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
