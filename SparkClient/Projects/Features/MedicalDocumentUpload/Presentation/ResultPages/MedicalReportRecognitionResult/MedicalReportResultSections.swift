import SwiftUI

struct MedicalReportMemberSectionView: View {
    let memberID: Int?
    let reports: [MedicalReportRecognitionDraft]

    var body: some View {
        MedicalReportResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalReportResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicalReportResultInfoLine(
                    title: L10n.text("medical.upload.result.medical_report.total_count"),
                    value: "\(reports.count)"
                )
            }
        }
    }
}

struct MedicalReportStatsSectionView: View {
    let reports: [MedicalReportRecognitionDraft]

    private var counts: [(MedicalReportDraftCategory, Int)] {
        MedicalReportDraftCategory.allCases.map { category in
            let count = reports.filter { MedicalReportDraftCategory.from($0.category) == category }.count
            return (category, count)
        }
    }

    var body: some View {
        MedicalReportResultSectionCard(
            title: L10n.text("medical.upload.result.medical_report.stats.title"),
            subtitle: L10n.text("medical.upload.result.medical_report.stats.subtitle"),
            systemImage: "chart.bar"
        ) {
            HStack(spacing: 10) {
                ForEach(counts, id: \.0.rawValue) { item in
                    statChip(category: item.0, value: item.1)
                }
            }
        }
    }

    private func statChip(category: MedicalReportDraftCategory, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                    .foregroundStyle(category.accentColor)
                Text(L10n.text(category.titleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct MedicalReportCardsSectionView: View {
    let reports: [MedicalReportRecognitionDraft]
    let onEdit: (Int, MedicalReportRecognitionDraft) -> Void

    var body: some View {
        MedicalReportResultSectionCard(
            title: L10n.text("medical.upload.result.medical_report.cards.title"),
            subtitle: L10n.text("medical.upload.result.medical_report.cards.subtitle"),
            systemImage: "doc.text.magnifyingglass",
            badgeText: String(
                format: L10n.text("medical.upload.result.medical_report.total_format"),
                locale: .current,
                reports.count
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(MedicalReportDraftCategory.allCases, id: \.rawValue) { category in
                    categoryBlock(category)
                }
            }
        }
    }

    private func categoryBlock(_ category: MedicalReportDraftCategory) -> some View {
        let indexed = reports.enumerated().filter { MedicalReportDraftCategory.from($0.element.category) == category }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                    .foregroundStyle(category.accentColor)
                Text(L10n.text(category.titleKey))
                    .font(.subheadline.weight(.semibold))
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
                Text(L10n.text("medical.upload.result.medical_report.empty_category"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                ForEach(indexed, id: \.offset) { pair in
                    reportRow(index: pair.offset, report: pair.element, category: category)
                }
            }
        }
    }

    private func reportRow(index: Int, report: MedicalReportRecognitionDraft, category: MedicalReportDraftCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(report.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Button(L10n.text("common.edit")) {
                    onEdit(index, report)
                }
                .font(.caption.weight(.semibold))
            }

            let header = [report.hospital, report.doctor, report.date]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            if header.isEmpty == false {
                Text(header)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(report.content.isEmpty ? "-" : report.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if report.details.isEmpty == false {
                Text(
                    String(
                        format: L10n.text("medical.upload.result.medical_report.detail_count"),
                        locale: .current,
                        report.details.count
                    )
                )
                .font(.caption)
                .foregroundStyle(category.accentColor)
                .monospacedDigit()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct MedicalReportAttachmentsSectionView: View {
    let attachments: [MedicalReportResultLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    var body: some View {
        MedicalReportResultSectionCard(
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

    private func row(_ item: MedicalReportResultLocalAttachmentItem) -> some View {
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
