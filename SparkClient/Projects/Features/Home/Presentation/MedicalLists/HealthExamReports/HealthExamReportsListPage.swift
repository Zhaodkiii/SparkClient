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
    private let notificationClient: any NotificationClient

    @State private var query = ""
    @State private var selectedFilter: HealthExamFilter = .all
    @State private var showingUploadSheet = false
    @State private var showingUploadHost = false

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        notificationClient: any NotificationClient,
        onReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)? = nil
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.notificationClient = notificationClient
        _viewModel = StateObject(
            wrappedValue: MedExamDetailLazyLoadViewModel(
                reports: completeData?.healthExamReports ?? [],
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "health_exam_reports",
                onReportsUpdated: onReportsUpdated
            )
        )
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

        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HealthExamSearchBar(text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                HealthExamFilterBar(selectedFilter: $selectedFilter)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            Divider()
                .opacity(0.35)

            ScrollView {
                examContent
                    .padding(.top, 8)
            }
            .refreshable {
                await refreshReports()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.health_exam_reports.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showingUploadSheet = true
            } label: {
                Label(L10n.text("home.medical.list.health_exam.action.camera_add_report", fallback: "拍摄添加体检报告"), systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(uiColor: .systemTeal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(memberID == nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicineBoxUploadSheet(
                title: L10n.text("medical.upload.health_exam_report.sheet.title", fallback: "选择体检报告"),
                headerTitle: L10n.text("medical.upload.health_exam_report.sheet.header", fallback: "选择上传方式"),
                headerSubtitle: L10n.text("medical.upload.health_exam_report.sheet.subtitle", fallback: "一次仅选择 1 个体检报告文件，确认后开始识别。"),
                emptyTitle: L10n.text("medical.upload.health_exam_report.sheet.empty.title", fallback: "尚未选择文件"),
                emptySubtitle: L10n.text("medical.upload.health_exam_report.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片"),
                fileNamePrefix: "health_exam_report",
                maxFileCount: 1
            ) { files in
                startHealthExamReportRecognition(files: files)
            }
        }
        .fullScreenCover(isPresented: $showingUploadHost) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(viewModel: medicalDocumentUploadViewModel)
            }
        }
    }

    @ViewBuilder
    private var examContent: some View {
        if filteredReports.isEmpty {
            HealthExamEmptyStateView()
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding(.vertical, 24)
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
                        }
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

    @MainActor
    private func refreshReports() async {
        guard let memberID else {
            logger.warning("体检列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("体检列表下拉刷新开始 memberID=\(memberID)", module: .home)

        do {
            // 下拉刷新只拉取体检报告列表，并只回写首页 completeData.healthExamReports 缓存字段。
            let refreshedReports = try await medicalQueryAPI.listHealthExamReportsWithAttachments(memberID: memberID)
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
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .healthExamReport)
        showingUploadHost = true
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

private struct HealthExamSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField(L10n.text("home.medical.list.health_exam.search.placeholder"), text: $text)
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
