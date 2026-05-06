import SwiftUI

/// 体检报告列表页：顶部搜索与筛选固定，正文展示体检卡片列表。
struct HealthExamReportsListPage: View {
    @StateObject private var viewModel: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>
    private let fileTransferService: FileTransferService

    @State private var query = ""
    @State private var selectedFilter: HealthExamFilter = .all

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        fileTransferService: FileTransferService,
        onReportsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)? = nil
    ) {
        self.fileTransferService = fileTransferService
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
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.health_exam_reports.title"))
        .navigationBarTitleDisplayMode(.inline)
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
                        fileTransferService: fileTransferService
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
