import SwiftUI

/// 医疗检查列表页：顶部固定搜索与分类，正文按分组展示检查卡片。
struct ExaminationReportsListPage: View {
    @StateObject private var viewModel: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments>
    private let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger
    private let fileTransferService: FileTransferService
    private let medicalResourceAPI: SparkMedicalWorkflowAPI
    @ObservedObject private var memberContextStore: MemberContextStore
    @ObservedObject private var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject private var aiSettingsViewModel: AISettingsViewModel
    private let notificationClient: any NotificationClient
    private let onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    /// 当前成员 ID；`complete-data` 缺失时为 0，此时不展示新增入口。
    private let memberID: Int

    @State private var query = ""
    @State private var selectedCategory: ExaminationReportCategory?
    @State private var isPresentingAddExamSheet = false
    /// 本页拍照上传 Sheet 与 OCR 识别流程共用的文档类型（须保持一致）。
    private static let uploadDocumentKind: MedicalDocumentKind = .medicalReport

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        notificationClient: any NotificationClient,
        onReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil,
        onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)? = nil
    ) {
        self.completeData = completeData
        self.memberID = completeData?.memberId ?? 0
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
        self.fileTransferService = fileTransferService
        self.medicalResourceAPI = SparkMedicalWorkflowAPI(configuration: medicalQueryAPI.configuration)
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.notificationClient = notificationClient
        self.onMedicalCasesUpdated = onMedicalCasesUpdated
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
            .refreshable {
                await refreshReports()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.examination_reports.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if memberID > 0 {
                MedicalListBottomActionBar(
                    documentKind: Self.uploadDocumentKind,
                    onManualAdd: { isPresentingAddExamSheet = true },
                    onUploadConfirmed: { files in startExaminationReportRecognition(files: files) }
                )
            }
        }
        .sheet(isPresented: $isPresentingAddExamSheet) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                ExamReportFormView(
                    mode: .create(
                        .init(
                            memberID: memberID,
                            medicalCaseID: nil,
                            submissionService: MedicalRecordFormSubmissionService(workflowAPI: medicalResourceAPI),
                            onCreated: { newID, draft in
                                let summary = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments.summaryAfterCreate(
                                    id: newID,
                                    memberID: memberID,
                                    draft: draft
                                )
                                viewModel.prependReport(summary)
                            }
                        )
                    )
                )
            }
        }
//        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
//            CompatibleNavigationContainer {
//                MedicalDocumentUploadHostView(
//                    viewModel: medicalDocumentUploadViewModel,
//                    aiSettingsViewModel: aiSettingsViewModel
//                )
//            }
//        }
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
                            completeData: completeData,
                            memberContextStore: memberContextStore,
                            notificationClient: notificationClient,
                            isLoading: { viewModel.isLoading(reportID: $0) },
                            onLoadDetails: { reportID in
                                Task {
                                    await viewModel.loadDetailsIfNeeded(for: reportID)
                                }
                            },
                            onDeleted: { deletedID in
                                viewModel.removeReport(reportID: deletedID)
                            },
                            onMedicalCaseLinked: { updated in
                                viewModel.upsertReport(updated)
                            },
                            onMedicalCaseUpdated: handleMedicalCaseUpdated,
                            onMedicalCaseDeleted: handleMedicalCaseDeleted,
                            onAttachmentsUpdated: { updated in
                                viewModel.upsertReport(updated)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func handleMedicalCaseUpdated(_ updated: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        var cases = completeData?.medicalCases ?? []
        if let index = cases.firstIndex(where: { $0.id == updated.id }) {
            cases[index] = updated
        } else {
            cases.insert(updated, at: 0)
        }
        onMedicalCasesUpdated?(cases)
    }

    private func handleMedicalCaseDeleted(_ deletedID: Int) {
        let cases = (completeData?.medicalCases ?? []).filter { $0.id != deletedID }
        onMedicalCasesUpdated?(cases)
    }

    @MainActor
    private func refreshReports() async {
        guard memberID > 0 else {
            logger.warning("检查报告列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("检查报告列表下拉刷新开始 memberID=\(memberID)", module: .home)

        do {
            // 下拉刷新只拉取检查报告列表，并只回写首页 completeData.examinationReports 缓存字段。
            let refreshedReports = try await medicalQueryAPI.listExaminationReportsWithAttachments(memberID: memberID)
            viewModel.replaceReports(refreshedReports)
            logger.info(
                "检查报告列表下拉刷新完成 memberID=\(memberID) count=\(refreshedReports.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
                module: .home
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.examination_reports.refresh")
            logger.warning("检查报告列表下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: .home)
        }
    }

    @MainActor
    private func startExaminationReportRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: Self.uploadDocumentKind)
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
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let isLoading: (Int) -> Bool
    let onLoadDetails: (Int) -> Void
    let onDeleted: (Int) -> Void
    let onMedicalCaseLinked: (SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void
    let onMedicalCaseUpdated: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void
    let onMedicalCaseDeleted: (Int) -> Void
    let onAttachmentsUpdated: (SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void

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
                        completeData: completeData,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient,
                        onDeleted: { deletedID in
                            onDeleted(deletedID)
                        },
                        onMedicalCaseLinked: { updated in
                            onMedicalCaseLinked(updated)
                        },
                        onMedicalCaseUpdated: { updated in
                            onMedicalCaseUpdated(updated)
                        },
                        onMedicalCaseDeleted: { deletedID in
                            onMedicalCaseDeleted(deletedID)
                        },
                        onAttachmentsUpdated: { updated in
                            onAttachmentsUpdated(updated)
                        }
                    )
                    .task {
                        onLoadDetails(report.id)
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
