import SwiftUI

/// 体检报告列表页：顶部搜索与筛选固定，正文展示体检卡片列表。
struct HealthExamReportsListPage: View {
    @StateObject private var viewModel: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>
    private let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    private let workflowAPI: SparkMedicalWorkflowAPI
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger
    private let fileTransferService: FileTransferService
    private let memberContextStore: MemberContextStore
    @ObservedObject private var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject private var aiSettingsViewModel: AISettingsViewModel
    private let notificationClient: any NotificationClient
    var archiveMode: MedicalArchiveListMode = .active

    @State private var selectedFilter: HealthExamFilter = .all
    /// 本页拍照上传 Sheet 与 OCR 识别流程共用的文档类型（须保持一致）。
    private static let uploadDocumentKind: MedicalDocumentKind = .healthExamReport

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        notificationClient: any NotificationClient,
        onReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)? = nil,
        archiveMode: MedicalArchiveListMode = .active
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.notificationClient = notificationClient
        self.archiveMode = archiveMode
        _viewModel = StateObject(
            wrappedValue: MedExamDetailLazyLoadViewModel(
                reports: archiveMode == .active ? (completeData?.healthExamReports ?? []) : [],
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "health_exam_reports",
                onReportsUpdated: archiveMode == .active ? onReportsUpdated : nil
            )
        )
    }

    private var navigationTitleText: String {
        archiveMode == .archived
            ? L10n.text("medical.archive.list.health_exam_reports.title")
            : L10n.text("home.medical.list.health_exam_reports.title")
    }

    private var reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] {
        viewModel.reports
    }

    private var memberID: Int? {
        completeData?.memberId ?? memberContextStore.context.selectedMember?.id
    }

    private var filteredReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] {
        var filtered = reports

        if selectedFilter != .all {
            filtered = filtered.filter { report in
                selectedFilter.matches(report)
            }
        }

        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return filtered }

        return filtered.filter { report in
            [
                report.institutionName,
                report.reportNo,
                report.summary
            ]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(keyword) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    examContent
                        .padding(.top, 8)
                } header: {
                    HealthExamFilterHeader(selectedFilter: $selectedFilter)
                }
            }
        }
        .refreshable {
            await refreshReports()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        // 👇 添加这两行，强制导航栏背景可见并且不透明
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar) // 你也可以换成 .white 等你想要的颜色
        .searchable(text: $viewModel.searchText, prompt: L10n.text("home.medical.family_cabinet.search_prompt"))
        .toolbar {
            if archiveMode == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    MainNavigationLink {
                        HealthExamReportsListPage(
                            completeData: completeData,
                            workflowAPI: workflowAPI,
                            medicalQueryAPI: medicalQueryAPI,
                            logger: logger,
                            fileTransferService: fileTransferService,
                            memberContextStore: memberContextStore,
                            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                            aiSettingsViewModel: aiSettingsViewModel,
                            notificationClient: notificationClient,
                            onReportsUpdated: nil,
                            archiveMode: .archived
                        )
                    } label: {
                        Text(L10n.text("medical.archive.list.entry"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if archiveMode == .active {
                MedicalListBottomActionBar(
                    documentKind: Self.uploadDocumentKind,
                    isEnabled: memberID != nil,
                    onUploadConfirmed: { files in startHealthExamReportRecognition(files: files) }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: archiveMode == .archived) {
            if archiveMode == .archived {
                await refreshReports()
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
    private var examContent: some View {
        if filteredReports.isEmpty {
            if archiveMode == .archived {
                Text(L10n.text("medical.archive.list.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                HealthExamEmptyStateView()
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .padding(.vertical, 24)
            }
        } else {
            LazyVStack(spacing: 16) {
                ForEach(filteredReports, id: \.id) { report in
                    ExamReportCard(
                        item: report,
                        isLoadingDetails: viewModel.isLoading(reportID: report.id),
                        fileTransferService: fileTransferService,
                        memberContextStore: memberContextStore,
                        workflowAPI: workflowAPI,
                        notificationClient: notificationClient,
                        onDeleted: { deletedID in
                            viewModel.removeReport(reportID: deletedID)
                        },
                        onArchiveStateChanged: handleArchiveStateChanged,
                        archiveMode: archiveMode
                    )
                    .task {
                        await viewModel.loadDetailsIfNeeded(for: report.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func handleArchiveStateChanged(id: Int, isArchived: Bool) {
        let belongsInList = archiveMode == .archived ? isArchived : !isArchived
        if belongsInList == false {
            viewModel.removeReport(reportID: id)
        }
    }

    @MainActor
    private func refreshReports() async {
        guard let memberID else {
            logger.warning("体检列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("体检列表下拉刷新开始 memberID=\(memberID) archiveMode=\(archiveMode)", module: .home)

        do {
            // 下拉刷新只拉取体检报告列表，并只回写首页 completeData.healthExamReports 缓存字段。
            let refreshedReports = try await medicalQueryAPI.listHealthExamReportsWithAttachments(
                memberID: memberID,
                archived: archiveMode.query
            )
            viewModel.replaceReports(refreshedReports)
            logger.info(
                "体检列表下拉刷新完成 memberID=\(memberID) count=\(refreshedReports.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
                module: .home
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.health_exam_reports.refresh")
            logger.warning("体检列表下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: .home)
        }
    }

    @MainActor
    private func startHealthExamReportRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: Self.uploadDocumentKind)
    }
}

private struct HealthExamFilterHeader: View {
    @Binding var selectedFilter: HealthExamFilter

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HealthExamFilterBar(selectedFilter: $selectedFilter)
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

private enum HealthExamFilter: CaseIterable, Identifiable {
    case all
    case withSummary
    case withAttachments

    var id: String {
        switch self {
        case .all: return "all"
        case .withSummary: return "withSummary"
        case .withAttachments: return "withAttachments"
        }
    }

    var titleKey: String {
        switch self {
        case .all:
            return "common.all"
        case .withSummary:
            return "home.medical.list.health_exam.filter.with_summary"
        case .withAttachments:
            return "home.medical.list.health_exam.filter.with_attachments"
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "list.bullet"
        case .withSummary:
            return "text.alignleft"
        case .withAttachments:
            return "paperclip"
        }
    }

    var color: Color {
        switch self {
        case .all:
            return Color(uiColor: .systemGray)
        case .withSummary:
            return Color(uiColor: .systemTeal)
        case .withAttachments:
            return Color(uiColor: .systemBlue)
        }
    }

    func matches(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) -> Bool {
        switch self {
        case .all:
            return true
        case .withSummary:
            return report.summary?.nonEmpty != nil
        case .withAttachments:
            return (report.attachments?.isEmpty == false)
        }
    }
}

private struct HealthExamFilterBar: View {
    @Binding var selectedFilter: HealthExamFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HealthExamFilter.allCases) { filter in
                    HealthExamFilterChip(
                        title: L10n.text(filter.titleKey),
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        color: filter.color
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct HealthExamFilterChip: View {
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

private struct HealthExamEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.health_exam.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.health_exam.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
