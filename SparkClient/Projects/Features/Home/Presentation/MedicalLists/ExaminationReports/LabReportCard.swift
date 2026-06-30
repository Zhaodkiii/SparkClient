import SwiftUI

/// 医疗检查卡片：结构参考 HealthClient `LabReportCard`，缺失字段仅留空展示。
struct LabReportCard: View {
    let item: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let category: ExaminationReportCategory
    var isLoadingDetails = false
    let fileTransferService: FileTransferService
    let medicalResourceAPI: SparkMedicalWorkflowAPI
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    var onDeleted: ((Int) -> Void)? = nil
    var onMedicalCaseLinked: ((SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void)? = nil
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil
    var onMedicalCaseDeleted: ((Int) -> Void)? = nil

    @State private var isExpanded = false
    @State private var isShowingAttachments = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var dateText: String {
        guard let date = item.reportedAt ?? item.performedAt else { return "" }
        return Self.dateFormatter.string(from: date)
    }

    private var titleText: String {
        item.itemName?.nonEmpty ?? ""
    }

    private var subtitleText: String {
        [item.category?.nonEmpty, item.subCategory?.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var hospitalText: String {
        item.organizationName?.nonEmpty ?? ""
    }

    private var detailText: String {
        item.impression?.nonEmpty ?? item.findings?.nonEmpty ?? ""
    }

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        item.medExamDetails ?? []
    }

    private var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] {
        item.attachments ?? []
    }

    private var abnormalDetailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        detailItems.filter { $0.flag.isPotentiallyAbnormal }
    }

    private var hasDetailText: Bool {
        detailText.isEmpty == false
    }

    private var canNavigateToDetail: Bool {
        detailItems.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(16)
                .background(Color.white.opacity(0.05))
                .overlay(alignment: .bottom) {
                    Divider()
                        .background(Color(uiColor: .separator).opacity(0.35))
                }

            if isLoadingDetails {
                loadingSection
            }

            cardContentSection
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.72))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    titleCluster
                    dateMetaRow
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 10) {
                    detailAction
                    MedicalAttachmentIconView(
                        count: attachments.count,
                        isExpanded: isShowingAttachments
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isShowingAttachments.toggle()
                        }
                    }
                }
            }

            if isShowingAttachments && attachments.isEmpty == false {
                MedicalAttachmentListView(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var detailAction: some View {
        if isLoadingDetails {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text("home.medical.list.examination.card.view_detail"))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
        } else if canNavigateToDetail {
            MainNavigationLink {
                detailDestination
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.text("home.medical.list.examination.card.view_detail"))
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 4) {
                Text(L10n.text("home.medical.list.examination.card.view_detail"))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .opacity(0.5)
        }
    }

    @ViewBuilder
    private var detailDestination: some View {
        ExaminationReportDetailHostPage(
            report: item,
            category: category,
            resources: medicalResourceAPI,
            fileTransferService: fileTransferService,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: notificationClient,
            onMedicalCaseLinked: onMedicalCaseLinked,
            onMedicalCaseUpdated: onMedicalCaseUpdated,
            onMedicalCaseDeleted: onMedicalCaseDeleted,
            onDeleted: onDeleted
        )
    }

    private var titleCluster: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if subtitleText.isEmpty == false {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dateMetaRow: some View {
        HStack(spacing: 12) {
            if dateText.isEmpty == false {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if hospitalText.isEmpty == false {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(hospitalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var cardContentSection: some View {
        switch category {
        case .laboratory:
            laboratorySection
        case .imaging:
            imagingSection
        case .pathology:
            pathologySection
        }
    }

    private var laboratorySection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatCardView(
                    value: "\(detailItems.count)",
                    label: L10n.text("home.medical.list.examination.card.items"),
                    backgroundColor: Color(uiColor: .systemBlue).opacity(0.08),
                    textColor: Color(uiColor: .systemBlue)
                )
                StatCardView(
                    value: "\(max(detailItems.count - abnormalDetailItems.count, 0))",
                    label: L10n.text("common.normal"),
                    backgroundColor: Color(uiColor: .systemGreen).opacity(0.08),
                    textColor: Color(uiColor: .systemGreen)
                )
                StatCardView(
                    value: "\(abnormalDetailItems.count)",
                    label: L10n.text("home.medical.list.examination.card.abnormal"),
                    backgroundColor: Color(uiColor: .systemRed).opacity(0.08),
                    textColor: Color(uiColor: .systemRed)
                )
            }
            .padding(16)

            if abnormalDetailItems.isEmpty == false {
                abnormalSection(
                    title: L10n.text("home.medical.list.examination.card.key_points"),
                    color: Color(uiColor: .systemOrange),
                    content: abnormalDetailItems
                        .prefix(5)
                        .map { "\($0.itemName)：\($0.resultValue ?? "")\($0.unit)" }
                        .joined(separator: "\n")
                )
            } else if hasDetailText {
                abnormalSection(
                    title: L10n.text("home.medical.list.examination.card.key_points"),
                    color: Color(uiColor: .systemOrange),
                    content: detailText
                )
            }
        }
    }

    private var imagingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(label: L10n.text("home.medical.list.examination.card.department"), value: item.departmentName?.nonEmpty ?? "")
            infoRow(label: L10n.text("home.medical.list.examination.card.doctor"), value: item.doctorName?.nonEmpty ?? "")
            
            // 临时隐藏
//            multilineInfoBlock(label: L10n.text("home.medical.list.examination.card.findings"), value: item.findings?.nonEmpty ?? "")
            multilineInfoBlock(label: L10n.text("home.medical.list.examination.card.impression"), value: item.impression?.nonEmpty ?? "")
            
            // 临时隐藏
//            detailItemsSection
        }
        .padding(16)
    }

    private var pathologySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(label: L10n.text("home.medical.list.examination.card.category"), value: item.category?.nonEmpty ?? "")
            infoRow(label: L10n.text("home.medical.list.examination.card.subcategory"), value: item.subCategory?.nonEmpty ?? "")
            multilineInfoBlock(label: L10n.text("home.medical.list.examination.card.findings"), value: item.findings?.nonEmpty ?? "")
            multilineInfoBlock(label: L10n.text("home.medical.list.examination.card.impression"), value: item.impression?.nonEmpty ?? "")
            detailItemsSection
        }
        .padding(16)
    }

    @ViewBuilder
    private var detailItemsSection: some View {
        if detailItems.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("home.medical.list.details.section"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(detailItems.prefix(5), id: \.id) { detail in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(detail.itemName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(detail.flag.nonEmpty ?? detail.resultValue ?? "")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(detail.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : .secondary)
                        }
                        Text([detail.resultValue ?? "", detail.unit].filter { $0.isEmpty == false }.joined())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var loadingSection: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.text("home.medical.list.details.loading"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.65))
    }

    private func abnormalSection(title: String, color: Color, content: String) -> some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(color)

                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(color)

                    Spacer()

                    Text("1")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color.opacity(0.85))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(color.opacity(0.05))
            .overlay(alignment: .bottom) {
                Divider()
                    .background(color.opacity(0.1))
            }

            if isExpanded {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(L10n.text("home.medical.list.examination.card.tap_to_expand"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(color.opacity(0.05))
        .overlay(alignment: .top) {
            Divider()
                .background(color.opacity(0.1))
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        if value.isEmpty == false {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func multilineInfoBlock(label: String, value: String) -> some View {
        if value.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct ExaminationReportDetailHostPage: View {
    @State private var report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let category: ExaminationReportCategory
    let resources: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    var onMedicalCaseLinked: ((SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void)?
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?
    var onDeleted: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingEditSheet = false
    @State private var isShowingDeleteAlert = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var mutationService: ExaminationReportServerMutationService {
        .init(resources: resources)
    }

    init(
        report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        category: ExaminationReportCategory,
        resources: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        onMedicalCaseLinked: ((SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void)?,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?,
        onMedicalCaseDeleted: ((Int) -> Void)?,
        onDeleted: ((Int) -> Void)? = nil
    ) {
        _report = State(initialValue: report)
        self.category = category
        self.resources = resources
        self.fileTransferService = fileTransferService
        self.completeData = completeData
        _memberContextStore = ObservedObject(wrappedValue: memberContextStore)
        self.notificationClient = notificationClient
        self.onMedicalCaseLinked = onMedicalCaseLinked
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
        self.onDeleted = onDeleted
    }

    private var existingDraft: MedicalReportRecognitionDraft {
        MedicalReportRecognitionDraft(
            category: report.category,
            title: report.itemName ?? "",
            hospital: report.organizationName,
            doctor: report.doctorName,
            content: report.impression?.nonEmpty ?? report.findings?.nonEmpty ?? "",
            date: MedicalDateCoding.encodeISO8601(report.reportedAt ?? report.performedAt ?? Date()),
            details: (report.medExamDetails ?? []).map {
                ItemDraft(medicalReportItem: MedicalReportItem(
                    category: $0.category,
                    subCategory: $0.subCategory,
                    itemName: $0.itemName,
                    itemCode: $0.itemCode,
                    resultValue: $0.resultValue,
                    unit: $0.unit,
                    referenceRange: $0.referenceRange,
                    flag: $0.flag,
                    resultAt: $0.resultAt.map(MedicalDateCoding.encodeISO8601),
                    modality: $0.modality,
                    bodyPart: $0.bodyPart,
                    diagnosis: $0.diagnosis,
                    extra: $0.extra,
                    sortOrder: "\($0.sortOrder)"
                ))
            }
        )
    }

    var body: some View {
        ExaminationReportSummaryDetailPage(
            report: $report,
            category: category,
            fileTransferService: fileTransferService,
            workflowAPI: resources,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: notificationClient,
            onMedicalCaseLinked: onMedicalCaseLinked,
            onMedicalCaseUpdated: onMedicalCaseUpdated,
            onMedicalCaseDeleted: onMedicalCaseDeleted
        )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("编辑") {
                            isShowingEditSheet = true
                        }
                        Button("删除", role: .destructive) {
                            isShowingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingEditSheet) {
                CompatibleNavigationContainer(legacyStackStyle: true) {
                    ExamReportFormView(
                        mode: .serverEdit(existing: report),
                        submissionService: MedicalRecordFormSubmissionService(workflowAPI: resources),
                        onReportDraftSaved: { draft in
                            report = report.applyingRecognitionDraft(draft)
                        }
                    )
                }
            }
            .alert("确认删除该检查报告？", isPresented: $isShowingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("确认删除", role: .destructive) {
                    guard isDeleting == false else { return }
                    isDeleting = true
                    Task {
                        do {
                            try await mutationService.deleteReport(reportID: report.id)
                            await MainActor.run {
                                onDeleted?(report.id)
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                            }
                        }
                        await MainActor.run {
                            isDeleting = false
                        }
                    }
                }
            } message: {
                Text("删除后无法恢复。")
            }
            .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if $0 == false { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
    /// 将表单/识别草稿合并到报告摘要与明细行（编辑保存与新建后列表回填共用）。
    func applyingRecognitionDraft(_ draft: MedicalReportRecognitionDraft) -> Self {
        var updated = self
        updated.category = draft.category ?? updated.category
        updated.itemName = draft.title
        updated.organizationName = draft.hospital
        updated.doctorName = draft.doctor
        updated.findings = draft.resolvedFindingsText
        updated.impression = draft.resolvedImpressionText
        updated.reportedAt = Date.parseOrNow(draft.date, defaultDate: reportedAt ?? performedAt ?? Date())
        updated.performedAt = updated.reportedAt
        updated.medExamDetails = draft.details.enumerated().map { index, row in
            SparkMedicalSyncAPI.RemoteMedExamDetail(
                id: index + 1,
                businessType: "examination_report",
                businessId: id,
                member: member,
                category: row.category ?? "",
                subCategory: row.subCategory ?? "",
                itemName: row.itemName?.nilIfBlank ?? "",
                itemCode: "",
                resultValue: row.resultValue?.nilIfBlank,
                unit: row.unit ?? "",
                referenceRange: row.referenceRange ?? "",
                flag: row.flag ?? "",
                resultAt: row.resultAt?.nilIfBlank.flatMap { value in
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Date.parseOrNow(value)
                },
                modality: row.modality ?? "",
                bodyPart: row.bodyPart ?? "",
                diagnosis: row.diagnosis?.nilIfBlank,
                extra: nil,
                sortOrder: index,
                updatedAt: Date()
            )
        }
        return updated
    }

    /// 新建接口返回 ID 后，构造列表展示用的摘要（含明细，避免立刻再请求明细）。
    static func summaryAfterCreate(id: Int, memberID: Int, draft: MedicalReportRecognitionDraft) -> Self {
        let now = Date()
        let shell = Self(
            id: id,
            member: memberID,
            medicalRecord: nil,
            category: draft.category ?? "laboratory",
            subCategory: nil,
            itemName: nil,
            performedAt: nil,
            reportedAt: nil,
            organizationName: nil,
            departmentName: nil,
            doctorName: nil,
            findings: nil,
            impression: nil,
            source: nil,
            status: nil,
            extra: nil,
            createdAt: now,
            updatedAt: now,
            attachments: [],
            medExamDetails: nil
        )
        return shell.applyingRecognitionDraft(draft)
    }
}
private struct StatCardView: View {
    let value: String
    let label: String
    let backgroundColor: Color
    let textColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(textColor)
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
