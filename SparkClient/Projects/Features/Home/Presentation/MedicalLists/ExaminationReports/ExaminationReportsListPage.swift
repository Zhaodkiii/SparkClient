import SwiftUI

/// 医疗检查列表页：顶部固定搜索与分类，正文按时间排序并按连续分类段落展示检查卡片。
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
    var archiveMode: MedicalArchiveListMode = .active

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
        onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)? = nil,
        archiveMode: MedicalArchiveListMode = .active
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
        self.archiveMode = archiveMode
        _viewModel = StateObject(
            wrappedValue: MedExamDetailLazyLoadViewModel(
                reports: archiveMode == .active ? (completeData?.examinationReports ?? []) : [],
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "examination_reports",
                onReportsUpdated: archiveMode == .active ? onReportsUpdated : nil
            )
        )
    }

    private var navigationTitleText: String {
        archiveMode == .archived
            ? L10n.text("medical.archive.list.examination_reports.title")
            : L10n.text("home.medical.list.examination_reports.title")
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

        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var timelineSections: [ExaminationReportTimelineSection] {
        ExaminationReportTimelineSection.makeSections(from: filteredReports)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    examinationContent
                        .padding(.top, 8)
                } header: {
                    ExaminationReportFilterHeader(selectedCategory: $selectedCategory)
                }
            }
        }
        .refreshable {
            await refreshReports()
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        // 👇 添加这两行，强制导航栏背景可见并且不透明
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar) // 你也可以换成 .white 等你想要的颜色
        .searchable(text: $viewModel.searchText, prompt: L10n.text("home.medical.family_cabinet.search_prompt"))
        .toolbar {
            if archiveMode == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    MainNavigationLink {
                        ExaminationReportsListPage(
                            completeData: completeData,
                            medicalQueryAPI: medicalQueryAPI,
                            logger: logger,
                            fileTransferService: fileTransferService,
                            memberContextStore: memberContextStore,
                            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                            aiSettingsViewModel: aiSettingsViewModel,
                            notificationClient: notificationClient,
                            onReportsUpdated: nil,
                            onMedicalCasesUpdated: onMedicalCasesUpdated,
                            archiveMode: .archived
                        )
                    } label: {
                        Text(L10n.text("medical.archive.list.entry"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if archiveMode == .active, memberID > 0 {
                MedicalListBottomActionBar(
                    documentKind: Self.uploadDocumentKind,
                    onManualAdd: { isPresentingAddExamSheet = true },
                    onUploadConfirmed: { files in startExaminationReportRecognition(files: files) }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: archiveMode == .archived) {
            if archiveMode == .archived {
                await refreshReports()
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
            if archiveMode == .archived {
                Text(L10n.text("medical.archive.list.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ExaminationReportsEmptyStateView()
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .padding(.vertical, 24)
            }
        } else {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(timelineSections) { section in
//                    ExaminationReportCategorySection(
//                        category: section.category,
//                        reports: section.reports,
//                        fileTransferService: fileTransferService,
//                        medicalResourceAPI: medicalResourceAPI,
//                        completeData: completeData,
//                        memberContextStore: memberContextStore,
//                        notificationClient: notificationClient,
//                        isLoading: { viewModel.isLoading(reportID: $0) },
//                        onLoadDetails: { reportID in
//                            Task {
//                                await viewModel.loadDetailsIfNeeded(for: reportID)
//                            }
//                        },
//                        onDeleted: { deletedID in
//                            viewModel.removeReport(reportID: deletedID)
//                        },
//                        onMedicalCaseLinked: { updated in
//                            viewModel.upsertReport(updated)
//                        },
//                        onMedicalCaseUpdated: handleMedicalCaseUpdated,
//                        onMedicalCaseDeleted: handleMedicalCaseDeleted,
//                        onAttachmentsUpdated: { updated in
//                            viewModel.upsertReport(updated)
//                        }
//                    )
                    Section {
                        ExaminationReportCategorySection(
                            category: section.category,
                            reports: section.reports,
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
                            },
                            onArchiveStateChanged: handleArchiveStateChanged,
                            archiveMode: archiveMode
                        )
                    } header: {
                        ExaminationReportTimelineSectionHeader(
                            category: section.category,
                            count: section.reports.count
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
}

private struct ExaminationReportFilterHeader: View {
    @Binding var selectedCategory: ExaminationReportCategory?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ExaminationReportFilterBar(selectedCategory: $selectedCategory)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            Divider()
                .opacity(0.35)
        }
    }
}

private struct ExaminationReportTimelineSectionHeader: View {
    let category: ExaminationReportCategory
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(category.color)

                    Text(L10n.text(category.titleKey))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            Divider()
                .opacity(0.35)
        }
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

    private func handleArchiveStateChanged(id: Int, isArchived: Bool) {
        let belongsInList = archiveMode == .archived ? isArchived : !isArchived
        if belongsInList == false {
            viewModel.removeReport(reportID: id)
        }
    }

    @MainActor
    private func refreshReports() async {
        guard memberID > 0 else {
            logger.warning("检查报告列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("检查报告列表下拉刷新开始 memberID=\(memberID) archiveMode=\(archiveMode)", module: .home)

        do {
            // 下拉刷新只拉取检查报告列表，并只回写首页 completeData.examinationReports 缓存字段。
            let refreshedReports = try await medicalQueryAPI.listExaminationReportsWithAttachments(
                memberID: memberID,
                archived: archiveMode.query
            )
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

struct ExaminationReportTimelineSection: Identifiable, Equatable {
    let category: ExaminationReportCategory
    var reports: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]

    var id: String {
        let firstID = reports.first?.id ?? -1
        let lastID = reports.last?.id ?? -1
        return "\(category.rawValue)-\(firstID)-\(lastID)-\(reports.count)"
    }

    static func makeSections(
        from reports: [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]
    ) -> [ExaminationReportTimelineSection] {
        let sortedReports = reports.enumerated().sorted { lhs, rhs in
            let lhsDate = lhs.element.timelineSortDate
            let rhsDate = rhs.element.timelineSortDate

            switch (lhsDate, rhsDate) {
            case let (left?, right?):
                if left == right {
                    return lhs.offset < rhs.offset
                }
                return left > right
            case (nil, nil):
                return lhs.offset < rhs.offset
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }

        var sections: [ExaminationReportTimelineSection] = []

        for indexedReport in sortedReports {
            let report = indexedReport.element
            let category = ExaminationReportCategory.category(for: report)

            if sections.last?.category == category {
                sections[sections.count - 1].reports.append(report)
            } else {
                sections.append(
                    ExaminationReportTimelineSection(
                        category: category,
                        reports: [report]
                    )
                )
            }
        }

        return sections
    }
}

private extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
    var timelineSortDate: Date? {
        reportedAt ?? performedAt
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
    var onArchiveStateChanged: ((Int, Bool) -> Void)? = nil
    var archiveMode: MedicalArchiveListMode = .active

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
//            HStack(spacing: 8) {
//                Image(systemName: category.icon)
//                    .font(.title3)
//                    .foregroundStyle(category.color)
//
//                Text(L10n.text(category.titleKey))
//                    .font(.headline)
//                    .fontWeight(.semibold)
//                    .foregroundStyle(.primary)
//
//                Spacer()
//
//                Text("\(reports.count)")
//                    .font(.subheadline)
//                    .monospacedDigit()
//                    .foregroundStyle(.secondary)
//                    .padding(.horizontal, 8)
//                    .padding(.vertical, 4)
//                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
//            }
//            .padding(.horizontal, 4)

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
                        },
                        onArchiveStateChanged: onArchiveStateChanged,
                        archiveMode: archiveMode
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
