import SwiftUI

// MARK: - 检查报告成员确认与统计概览区块视图
/// 检查报告识别结果页：展示就诊人、成员切换与报告分类统计
struct MedicalReportMemberConfirmSectionView: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    let reports: [MedicalReportRecognitionDraft]
    var onSelectMember: ((Int?) -> Void)?
    
    private var selectedMemberName: String {
        guard let selectedMemberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return memberContextStore.context.members.first(where: { $0.id == selectedMemberID })?.name
        ?? "\(selectedMemberID)"
    }
    
    private var categoryCounts: [(ExaminationReportCategory, Int)] {
        ExaminationReportCategory.allCases.map { category in
            let count = reports.filter { ExaminationReportCategory.from($0.category) == category }.count
            return (category, count)
        }
    }
    
    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.medical_report.member.subtitle", fallback: "确认保存到该成员的检查报告"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                memberRow
                overviewContent
            }
        }
    }
    
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .symbolRenderingMode(.hierarchical)
                
                Text(L10n.text("medical.upload.result.medical_report.stats.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 0)
            }
            
            //            Text(L10n.text("medical.upload.result.medical_report.stats.subtitle"))
            //                .font(.callout)
            //                .foregroundStyle(.secondary)
            //
            //            MedicalDocumentResultInfoLine(
            //                title: L10n.text("medical.upload.result.medical_report.total_count"),
            //                value: "\(reports.count)"
            //            )
            
            HStack(spacing: 10) {
                ForEach(categoryCounts, id: \.0.rawValue) { item in
                    statChip(category: item.0, value: item.1)
                }
            }
        }
    }
    
    @ViewBuilder
    private var memberRow: some View {
        if let onSelectMember {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("medical.upload.result.member.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                MemberProfileBindingMenu(
                    memberContextStore: memberContextStore,
                    selectedMemberID: selectedMemberID,
                    onSelect: onSelectMember
                ) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.accentColor)
                        Text(selectedMemberName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }
        } else {
            MedicalDocumentResultInfoLine(
                title: L10n.text("medical.upload.result.member.id"),
                value: selectedMemberName
            )
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
    var validationIssues: [MedicalPreSubmitValidationIssue] = []
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    var detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    let onUpdateReportDraft: (Int, MedicalReportRecognitionDraft) -> Void
    let onDeleteReportDraft: (Int) -> Void
    let onManageAttachments: (Int) -> Void
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ExaminationReportCategory.allCases, id: \.rawValue) { category in
                    categoryBlock(category)
                }
            }
        } header: {
            sectionHeader
                .contentShape(Rectangle())
        }
    }
    
    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .symbolRenderingMode(.hierarchical)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("medical.upload.result.medical_report.cards.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text(L10n.text("medical.upload.result.medical_report.cards.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            Text(
                String(
                    format: L10n.text("medical.upload.result.medical_report.total_format"),
                    locale: .current,
                    reports.count
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
        }
    }
    
    @ViewBuilder
    private func categoryBlock(_ category: ExaminationReportCategory) -> some View {
        let indexed = reports.enumerated().filter { ExaminationReportCategory.from($0.element.category) == category }
        if indexed.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
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
                ForEach(indexed, id: \.offset) { pair in
                    reportCard(index: pair.offset, report: pair.element, category: category)
                }
            }
        }
    }
    
    @ViewBuilder
    private func reportCard(index: Int, report: MedicalReportRecognitionDraft, category: ExaminationReportCategory) -> some View {
        if let detailNavigationContext {
            MainNavigationLink {
                reportDetailDestination(index: index, report: report, category: category, context: detailNavigationContext)
            } label: {
                reportCardContent(index: index, report: report, category: category)
            }
            .buttonStyle(.plain)
        } else {
            reportCardContent(index: index, report: report, category: category)
        }
    }
    
    private func reportCardContent(index: Int, report: MedicalReportRecognitionDraft, category: ExaminationReportCategory) -> some View {
        let cardIssues = validationIssues.issues(forCardIndex: index, resourceType: .examinationReport)
        let hasError = cardIssues.isEmpty == false
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(report.title.nilIfBlank ?? L10n.text("medical.upload.presubmit.value.not_filled"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(hasError ? .red : .primary)
                    .lineLimit(1)
                Spacer()
                if hasError {
                    MedicalValidationIssueBadge()
                }
                if detailNavigationContext != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.gray)
                }
            }
            .contentShape(Rectangle())
            
            ForEach(cardIssues.prefix(3)) { issue in
                MedicalValidationIssueInlineView(message: issue.summaryLine)
            }
            
            let header = [report.hospital, report.doctor, report.date]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            if header.isEmpty == false {
                Text(header)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            draftClinicalTextBlocks(for: report, category: category)
            
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
            
            if let attachmentsForIDs, report.attachmentFileIds.isEmpty == false {
                CaseMatchedAttachmentsGridView(
                    title: "匹配附件",
                    attachments: attachmentsForIDs(report.attachmentFileIds),
                    onManage: {
                        onManageAttachments(index)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
        .medicalValidationCardChrome(
            hasError: hasError,
            scrollTargetID: "preSubmitValidation.card.examinationReport.\(index)"
        )
    }

    @ViewBuilder
    private func draftClinicalTextBlocks(
        for report: MedicalReportRecognitionDraft,
        category: ExaminationReportCategory
    ) -> some View {
        switch category {
        case .imaging, .pathology:
            if let findings = report.resolvedFindingsText {
                draftClinicalTextBlock(
                    title: L10n.text("home.medical.list.examination.card.findings"),
                    body: findings
                )
            }
            if let impression = report.resolvedImpressionText,
               impression != report.resolvedFindingsText {
                draftClinicalTextBlock(
                    title: L10n.text("home.medical.list.examination.card.impression"),
                    body: impression
                )
            }
            if report.resolvedFindingsText == nil, report.resolvedImpressionText == nil {
                Text("-")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        case .laboratory:
            Text(report.content?.nonEmpty ?? "-")
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }

    private func draftClinicalTextBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
    }
    
    private func reportDetailDestination(
        index: Int,
        report: MedicalReportRecognitionDraft,
        category: ExaminationReportCategory,
        context: MedicalDocumentResultDetailNavigationContext
    ) -> some View {
        let matched = attachmentsForIDs?(report.attachmentFileIds) ?? []
        return ExaminationReportDetailPage(
            mode: .localDraft,
            report: report.remoteExaminationReport(
                memberID: context.memberID,
                id: PrescriptionRecognitionDraftMapper.temporaryExaminationReportID(index: index)
            ),
            category: category,
            fileTransferService: context.fileTransferService,
            memberContextStore: context.memberContextStore,
            localAttachments: matched,
            sourceReportDraft: report,
            onSaved: { _ in },
            onDeleted: { _ in },
            onLocalDraftSaved: { updated in
                onUpdateReportDraft(index, updated)
            },
            onLocalDraftDeleted: {
                onDeleteReportDraft(index)
            }
        )
    }
}
