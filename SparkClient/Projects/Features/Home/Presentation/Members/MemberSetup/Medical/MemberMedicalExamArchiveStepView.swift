import SwiftUI

struct MemberMedicalExamArchiveStepView: View {
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    @Binding var hasExamHistory: Bool

    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let notificationClient: any NotificationClient

    @State private var showingUploadSheet = false
    @State private var reportDetailLoader: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>?

    private let logger: Logger = ConsoleLogger()

    private var memberID: Int {
        viewModel.member?.id ?? 0
    }

    private var workflowAPI: SparkMedicalWorkflowAPI {
        viewModel.medicalWorkflowAPI
    }

    private var sortedReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] {
        viewModel.memberHealthExamReports.sorted {
            ($0.examDate ?? .distantPast) > ($1.examDate ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            examHistoryScreeningCard

            if hasExamHistory {
                if viewModel.isLoadingMemberHealthExamReports && sortedReports.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    examReportListSection
                    examHistoryCompletionCard
                }
            }
        }
        .task(id: memberID) {
            await loadExamArchive()
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .healthExamReport, onConfirm: startHealthExamRecognition)
        }
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
            }
        }
        .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task { await refreshAfterMedicalUploadSave() }
        }
        .onChange(of: hasExamHistory) { newValue in
            if newValue == false {
                showingUploadSheet = false
            } else if sortedReports.isEmpty {
                Task { await loadExamArchive() }
            }
        }
        .onChange(of: viewModel.memberHealthExamReports) { reports in
            reportDetailLoader?.replaceReports(reports)
        }
    }

    private var examHistoryScreeningCard: some View {
        MemberSetupSection(title: "是否有历史体检报告") {
            HStack(spacing: 10) {
                screeningChoice(
                    title: "暂无历史报告",
                    isSelected: hasExamHistory == false,
                    action: { hasExamHistory = false }
                )
                screeningChoice(
                    title: "有历史报告",
                    isSelected: hasExamHistory,
                    action: { hasExamHistory = true }
                )
            }
        }
    }

    @ViewBuilder
    private var examReportListSection: some View {
        if sortedReports.isEmpty {
            MemberSetupSection(title: "体检报告列表") {
                Text("暂无已导入报告，可通过下方拍照或上传电子版快速录入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let reportDetailLoader {
            MemberSetupSection(title: "体检报告列表") {
                VStack(spacing: 12) {
                    ForEach(sortedReports, id: \.id) { report in
                        ExamReportCard(
                            item: report,
                            isLoadingDetails: reportDetailLoader.isLoading(reportID: report.id),
                            fileTransferService: fileTransferService,
                            memberContextStore: memberContextStore,
                            workflowAPI: workflowAPI,
                            notificationClient: notificationClient,
                            onDeleted: { deletedID in
                                viewModel.removeHealthExamReport(id: deletedID)
                                reportDetailLoader.removeReport(reportID: deletedID)
                            }
                        )
                        .task {
                            await reportDetailLoader.loadDetailsIfNeeded(for: report.id)
                        }
                    }
                }
            }
        }
    }

    private var examHistoryCompletionCard: some View {
        MemberSetupSection(title: "历史体检信息补全") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("最近一次体检时间", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: lastExamDateBinding,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("电子体检报告导入 (推荐)")
                        .font(.subheadline.weight(.semibold))

                    Text("系统将启动 AI 智能 OCR 识别，自动提取您的异常指标与结论。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        importActionButton(
                            title: "拍照 / 扫描纸质报告",
                            systemImage: "camera.viewfinder",
                            isPrimary: true
                        ) {
                            showingUploadSheet = true
                        }

                        importActionButton(
                            title: "上传电子版 (PDF/图片)",
                            systemImage: "folder",
                            isPrimary: false
                        ) {
                            showingUploadSheet = true
                        }
                    }
                }
            }
        }
    }

    private var lastExamDateBinding: Binding<Date> {
        Binding(
            get: {
                MemberMedicalSetupViewModel.date(fromYearMonth: viewModel.lastExamYear) ?? Date()
            },
            set: { newValue in
                viewModel.lastExamYear = MemberMedicalSetupViewModel.yearMonthString(from: newValue)
            }
        )
    }

    private func importActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPrimary ? Color.accentColor : Color(uiColor: .systemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadExamArchive() async {
        guard memberID > 0 else { return }

        if reportDetailLoader == nil {
            reportDetailLoader = MedExamDetailLazyLoadViewModel(
                reports: viewModel.memberHealthExamReports,
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "medical_setup_exam_archive",
                onReportsUpdated: { reports in
                    viewModel.syncHealthExamReportsCache(reports)
                }
            )
        }

        await viewModel.refreshMemberHealthExamReportsIfNeeded(force: true)
        reportDetailLoader?.replaceReports(viewModel.memberHealthExamReports)
    }

    @MainActor
    private func refreshAfterMedicalUploadSave() async {
        await viewModel.refreshMemberHealthExamReportsIfNeeded(force: true)
        reportDetailLoader?.replaceReports(viewModel.memberHealthExamReports)
        hasExamHistory = true
    }

    @MainActor
    private func startHealthExamRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .healthExamReport)
    }
}
