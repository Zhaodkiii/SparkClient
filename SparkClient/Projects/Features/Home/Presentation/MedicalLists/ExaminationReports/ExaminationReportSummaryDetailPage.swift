import SwiftUI

/// 检查报告总览：展示报告级字段、关联病历与子项导航。
struct ExaminationReportSummaryDetailPage: View {
    @Binding var report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let category: ExaminationReportCategory
    var fileTransferService: FileTransferService?
    var workflowAPI: SparkMedicalWorkflowAPI?
    var completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    var notificationClient: (any NotificationClient)?
    var onMedicalCaseLinked: ((SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void)?
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    private var sortedDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        (report.medExamDetails ?? []).sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var navigationTitleText: String {
        report.itemName?.nonEmpty ?? L10n.text("home.medical.list.examination_reports.title")
    }

    private var headerSubtitle: String {
        [
            (report.reportedAt ?? report.performedAt).map { $0.formatted(date: .abbreviated, time: .omitted) },
            report.organizationName?.nonEmpty
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                findingsAndImpressionSection
                attachmentsSection
                subitemsSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [category.color, category.color.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: category.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(navigationTitleText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if headerSubtitle.isEmpty == false {
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
            }

            detailGrid

            medicalCaseLinkSectionContent
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var medicalCaseLinkSectionContent: some View {
        if let workflowAPI, let notificationClient, let fileTransferService {
            MedicalResourceMedicalCaseLinkSection(
                memberID: report.member,
                medicalCaseID: report.medicalRecord,
                resourceKind: .examinationReports,
                resourceID: report.id,
                patchField: .medicalRecord,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                completeData: completeData,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient,
                linkedTitle: L10n.text("home.medical.list.examination.linked_case.title", fallback: "已关联病历"),
                linkedSubtitle: L10n.text("home.medical.list.examination.linked_case.subtitle", fallback: "点击查看关联病历详情"),
                unlinkedTitle: L10n.text("home.medical.list.examination.unlinked_case.title", fallback: "关联病历"),
                unlinkedSubtitle: L10n.text("home.medical.list.examination.unlinked_case.subtitle", fallback: "把这份检查报告归入一次就诊或病例"),
                onResourceUpdated: { (updated: SparkMedicalSyncAPI.RemoteExaminationReport) in
                    var merged = report
                    merged.medicalRecord = updated.medicalRecord
                    merged.updatedAt = updated.updatedAt
                    report = merged
                    onMedicalCaseLinked?(merged)
                },
                onMedicalCaseUpdated: onMedicalCaseUpdated,
                onMedicalCaseDeleted: onMedicalCaseDeleted
            )
        }
    }

    private var detailGrid: some View {
        VStack(spacing: 10) {
            ExaminationReportSummaryInfoRow(title: "报告类型", value: L10n.text(category.titleKey))
            ExaminationReportSummaryInfoRow(title: "大类", value: report.category?.nonEmpty ?? "未填写")
            ExaminationReportSummaryInfoRow(title: "细类", value: report.subCategory?.nonEmpty ?? "未填写")
            ExaminationReportSummaryInfoRow(
                title: "检查日期",
                value: report.performedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "未填写"
            )
            ExaminationReportSummaryInfoRow(
                title: "报告日期",
                value: report.reportedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "未填写"
            )
            ExaminationReportSummaryInfoRow(title: "机构", value: report.organizationName?.nonEmpty ?? "未填写")
            ExaminationReportSummaryInfoRow(title: "科室", value: report.departmentName?.nonEmpty ?? "未填写")
            ExaminationReportSummaryInfoRow(title: "医生", value: report.doctorName?.nonEmpty ?? "未填写")
            if let source = report.source {
                ExaminationReportSummaryInfoRow(title: "来源", value: "\(source)")
            }
            if let status = report.status {
                ExaminationReportSummaryInfoRow(title: "状态", value: "\(status)")
            }
        }
    }

    @ViewBuilder
    private var findingsAndImpressionSection: some View {
        let findings = report.findings?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let impression = report.impression?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if findings.isEmpty == false {
            narrativeCard(
                title: "所见",
                systemImage: "text.alignleft",
                tint: Color(uiColor: .systemTeal),
                text: findings
            )
        }

        if impression.isEmpty == false, impression != findings {
            narrativeCard(
                title: "印象",
                systemImage: "text.quote",
                tint: Color(uiColor: .systemIndigo),
                text: impression
            )
        }
    }

    private func narrativeCard(title: String, systemImage: String, tint: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        let attachments = report.attachments ?? []
        if let fileTransferService, attachments.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.text("common.attachments"), systemImage: "paperclip")
                    .font(.headline)
                MedicalAttachmentGridPreview(attachments: attachments, fileTransferService: fileTransferService)
//                MedicalAttachmentListView(attachments: attachments, fileTransferService: fileTransferService)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var subitemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("检查明细", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(sortedDetails.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if category == .laboratory {
                    NavigationLink {
                        LaboratoryReportDetailPage(
                            report: report.replacingMedExamDetails(sortedDetails),
                            navigationTitleOverride: nil
                        )
                    } label: {
                        HStack {
                            Text("查看完整检验表")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        
                    }
                    .buttonStyle(.plain)
                    .disabled(sortedDetails.isEmpty)
                }
            }
            if sortedDetails.isEmpty {
                Text("暂无检查细项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }  else {
                VStack(spacing: 10) {
                    ForEach(sortedDetails, id: \.id) { item in
                        NavigationLink {
                            ExaminationReportCategoryDetailPage(
                                category: category,
                                report: report.replacingMedExamDetails([item]),
                                navigationTitleOverride: item.itemName
                            )
                        } label: {
                            ExaminationReportSubitemSummaryRow(category: category, item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 分类对应的明细页路由（实验室表格 / 影像卡片 / 病理卡片）。
struct ExaminationReportCategoryDetailPage: View {
    let category: ExaminationReportCategory
    let report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    var navigationTitleOverride: String? = nil

    var body: some View {
        switch category {
//        case .laboratory:
//            LaboratoryReportDetailPage(report: report, navigationTitleOverride: navigationTitleOverride)
        case .imaging,.laboratory:
            ImagingReportDetailPage(report: report, navigationTitleOverride: navigationTitleOverride)
        case .pathology:
            PathologyReportDetailPage(report: report, navigationTitleOverride: navigationTitleOverride)
        }
    }
}

private struct ExaminationReportSummaryInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ExaminationReportSubitemSummaryRow: View {
    let category: ExaminationReportCategory
    let item: SparkMedicalSyncAPI.RemoteMedExamDetail
    var showsTrailingChevron: Bool = true

    private var subtitle: String {
        switch category {
        case .laboratory:
            return [
                [item.resultValue ?? "", item.unit].filter { $0.isEmpty == false }.joined(),
                item.referenceRange.nonEmpty.map { "参考 \($0)" },
                item.flag.nonEmpty
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        case .imaging:
            return [
                item.modality.nonEmpty,
                item.bodyPart.nonEmpty,
                [item.resultValue ?? "", item.unit].filter { $0.isEmpty == false }.joined()
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        case .pathology:
            return [
                [item.resultValue ?? "", item.unit].filter { $0.isEmpty == false }.joined(),
                item.diagnosis?.nonEmpty
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(category.color.opacity(0.14))
                Image(systemName: category.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(category.color)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.itemName.isEmpty ? "未命名项目" : item.itemName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle.isEmpty ? "点击查看详情" : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if showsTrailingChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
    /// 构造仅包含指定明细行的报告副本，用于子项导航上下文。
    func replacingMedExamDetails(_ details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?) -> Self {
        var copy = self
        copy.medExamDetails = details
        return copy
    }
}
