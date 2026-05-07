import SwiftUI

/// 医疗检查列表页：顶部固定搜索与分类，正文按分组展示检查卡片。
struct ExaminationReportsListPage: View {
    @StateObject private var viewModel: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments>
    private let fileTransferService: FileTransferService
    private let medicalResourceAPI: SparkMedicalWorkflowAPI
    /// 当前成员 ID；`complete-data` 缺失时为 0，此时不展示新增入口。
    private let memberID: Int

    @State private var query = ""
    @State private var selectedCategory: ExaminationReportCategory?
    @State private var isPresentingAddExamSheet = false

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        fileTransferService: FileTransferService,
        onReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil
    ) {
        self.memberID = completeData?.memberId ?? 0
        self.fileTransferService = fileTransferService
        self.medicalResourceAPI = SparkMedicalWorkflowAPI(configuration: medicalQueryAPI.configuration)
        _viewModel = StateObject(
            wrappedValue: MedExamDetailLazyLoadViewModel(
                reports: completeData?.examinationReports ?? [],
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "examination_reports",
                onReportsUpdated: onReportsUpdated
            )
        )
    }

    private var reports: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments] {
        viewModel.reports
    }

    /// 仅做界面过滤，不触发二次加载。
    private var filteredReports: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments] {
        var filtered = reports

        if let selectedCategory {
            filtered = filtered.filter { selectedCategory.matches($0) }
        }

        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return filtered }

        return filtered.filter { report in
            [
                report.itemName,
                report.category,
                report.subCategory,
                report.organizationName,
                report.departmentName,
                report.doctorName,
                report.findings,
                report.impression
            ]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(keyword) }
        }
    }

    private var groupedReports: [ExaminationReportCategory: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]] {
        Dictionary(grouping: filteredReports) { report in
            ExaminationReportCategory.allCases.first(where: { $0.matches(report) }) ?? .laboratory
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ExaminationReportSearchBar(text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ExaminationReportFilterBar(selectedCategory: $selectedCategory)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            Divider()
                .opacity(0.35)

            ScrollView {
                examinationContent
                    .padding(.top, 8)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.examination_reports.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if memberID > 0 {
                Button {
                    isPresentingAddExamSheet = true
                } label: {
                    Label(L10n.text("home.medical.list.examination.action.add"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .sheet(isPresented: $isPresentingAddExamSheet) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                ExamReportFormView(mode: .create, onCreateSubmit: { draft in
                    let service = MedicalRecordFormSubmissionService(workflowAPI: medicalResourceAPI)
                    let newID = try await service.submitMedicalReportCreate(memberID: memberID, draft: draft, medicalCaseID: nil)
                    let summary = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments.summaryAfterCreate(
                        id: newID,
                        memberID: memberID,
                        draft: draft
                    )
                    await MainActor.run {
                        viewModel.prependReport(summary)
                    }
                })
            }
        }
    }

    @ViewBuilder
    private var examinationContent: some View {
        if filteredReports.isEmpty {
            ExaminationReportsEmptyStateView()
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(ExaminationReportCategory.allCases) { category in
                    if let reports = groupedReports[category], reports.isEmpty == false {
                        ExaminationReportCategorySection(
                            category: category,
                            reports: reports,
                            fileTransferService: fileTransferService,
                            medicalResourceAPI: medicalResourceAPI,
                            isLoading: { viewModel.isLoading(reportID: $0) },
                            onLoadDetails: { reportID in
                                await viewModel.loadDetailsIfNeeded(for: reportID)
                            },
                            onDeleted: { deletedID in
                                viewModel.removeReport(reportID: deletedID)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

private struct ExaminationReportSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField(L10n.text("home.medical.list.examination.search.placeholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.body)

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ExaminationReportFilterBar: View {
    @Binding var selectedCategory: ExaminationReportCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ExaminationReportFilterChip(
                    title: L10n.text("common.all"),
                    icon: "list.bullet",
                    isSelected: selectedCategory == nil,
                    color: Color(uiColor: .systemGray)
                ) {
                    selectedCategory = nil
                }

                ForEach(ExaminationReportCategory.allCases) { category in
                    ExaminationReportFilterChip(
                        title: L10n.text(category.titleKey),
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        color: category.color
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct ExaminationReportFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(isSelected ? Color.white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? color : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ExaminationReportCategorySection: View {
    let category: ExaminationReportCategory
    let reports: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]
    let fileTransferService: FileTransferService
    let medicalResourceAPI: SparkMedicalWorkflowAPI
    let isLoading: (Int) -> Bool
    let onLoadDetails: (Int) async -> Void
    let onDeleted: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)

                Text(L10n.text(category.titleKey))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(reports.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 12) {
                ForEach(reports, id: \.id) { report in
                    LabReportCard(
                        item: report,
                        category: category,
                        isLoadingDetails: isLoading(report.id),
                        fileTransferService: fileTransferService,
                        medicalResourceAPI: medicalResourceAPI,
                        onDeleted: { deletedID in
                            onDeleted(deletedID)
                        }
                    )
                    .task {
                        await onLoadDetails(report.id)
                    }
                }
            }
        }
    }
}

private struct ExaminationReportsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "testtube.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.examination.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.examination.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
