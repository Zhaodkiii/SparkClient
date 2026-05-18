import SwiftUI

struct MedicalReportMemberSectionView: View {
    let memberID: Int?
    let reports: [MedicalReportRecognitionDraft]

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark",
            tintColor: Color(uiColor: .systemTeal)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.member.id"),
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicalDocumentResultInfoLine(
                    title: L10n.text("medical.upload.result.medical_report.total_count"),
                    value: "\(reports.count)"
                )
            }
        }
    }
}

struct MedicalReportStatsSectionView: View {
    let reports: [MedicalReportRecognitionDraft]

    private var counts: [(ExaminationReportCategory, Int)] {
        ExaminationReportCategory.allCases.map { category in
            let count = reports.filter { ExaminationReportCategory.from($0.category) == category }.count
            return (category, count)
        }
    }

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.medical_report.stats.title"),
            subtitle: L10n.text("medical.upload.result.medical_report.stats.subtitle"),
            systemImage: "chart.bar",
            tintColor: Color(uiColor: .systemTeal)
        ) {
            HStack(spacing: 10) {
                ForEach(counts, id: \.0.rawValue) { item in
                    statChip(category: item.0, value: item.1)
                }
            }
        }
    }

    private func statChip(category: ExaminationReportCategory, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(category.color)
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
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    let onEdit: (Int, MedicalReportRecognitionDraft) -> Void
    var onManageAttachments: ((Int, MedicalReportRecognitionDraft) -> Void)?

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.medical_report.cards.title"),
            subtitle: L10n.text("medical.upload.result.medical_report.cards.subtitle"),
            systemImage: "doc.text.magnifyingglass",
            tintColor: Color(uiColor: .systemTeal),
            badgeText: String(
                format: L10n.text("medical.upload.result.medical_report.total_format"),
                locale: .current,
                reports.count
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ExaminationReportCategory.allCases, id: \.rawValue) { category in
                    categoryBlock(category)
                }
            }
        }
    }

    private func categoryBlock(_ category: ExaminationReportCategory) -> some View {
        let indexed = reports.enumerated().filter { ExaminationReportCategory.from($0.element.category) == category }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(category.color)
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

    private func reportRow(index: Int, report: MedicalReportRecognitionDraft, category: ExaminationReportCategory) -> some View {
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
                .foregroundStyle(category.color)
                .monospacedDigit()
            }

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "匹配附件",
                    attachments: attachmentsForIDs(report.attachmentFileIds),
                    onManage: {
                        onManageAttachments?(index, report)
                    }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
