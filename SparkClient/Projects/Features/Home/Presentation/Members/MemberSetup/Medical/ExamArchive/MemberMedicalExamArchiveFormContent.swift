import SwiftUI

/// 体检档案主表单（是否有报告 + 补全/列表），样式与 `MemberMedicalExamArchiveStepView` 一致。
struct MemberMedicalExamArchiveFormContent: View {
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    @ObservedObject var flowViewModel: MemberMedicalExamArchiveFlowViewModel
    @Binding var hasExamHistory: Bool

    let fileTransferService: FileTransferService
    let medicalQueryAPI: SparkMedicalQueryAPI
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let workflowAPI: SparkMedicalWorkflowAPI
    let notificationClient: any NotificationClient

    var onReportSelected: (SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) -> Void

    @State private var showingUploadSheet = false
    @State private var reportDetailLoader: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>?

    private let logger: Logger = ConsoleLogger()

    private var sortedReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] {
        flowViewModel.healthExamReports.sorted {
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
                } else if sortedReports.isEmpty {
                    examHistoryCompletionCard
                } else if let reportDetailLoader {
                    examReportListSection(reportDetailLoader: reportDetailLoader)
                }
            }
        }
        .task(id: viewModel.member?.id) {
            await loadExamArchiveIfNeeded()
        }
        .onChange(of: viewModel.memberHealthExamReports) { reports in
            flowViewModel.refreshReports(reports)
            reportDetailLoader?.replaceReports(reports)
        }
        .onChange(of: hasExamHistory) { newValue in
            if newValue == false {
                showingUploadSheet = false
            } else {
                Task { await loadExamArchiveIfNeeded() }
            }
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
    }

    private var examHistoryScreeningCard: some View {
        MemberSetupSection(title: "是否有历史体检报告") {
            HStack(spacing: 10) {
                screeningChoice(title: "暂无历史报告", isSelected: hasExamHistory == false) {
                    hasExamHistory = false
                    flowViewModel.selectPath(.noHistoryReport)
                }
                screeningChoice(title: "有历史报告", isSelected: hasExamHistory) {
                    hasExamHistory = true
                    flowViewModel.selectPath(.hasHistoryReport)
                }
            }
        }
    }

    @ViewBuilder
    private func examReportListSection(
        reportDetailLoader: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.bold))
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                Text("体检报告列表")
                    .font(.title2.weight(.bold))
                Spacer(minLength: 0)
                importActionButton(
                    title: "拍照 / 扫描纸质报告",
                    systemImage: "camera.viewfinder",
                    isPrimary: true
                ) {
                    showingUploadSheet = true
                }
            }

            VStack(spacing: 12) {
                ForEach(sortedReports, id: \.id) { report in
                    Button {
                        onReportSelected(report)
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .task {
                        await reportDetailLoader.loadDetailsIfNeeded(for: report.id)
                    }
                }
            }

            Text("点击报告卡片进入 AI 异常项确认与体检计划生成。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

                HStack {
                    Label("体检机构/医院", systemImage: "building.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("请输入体检中心名称", text: $viewModel.examInstitution)
                        .multilineTextAlignment(.trailing)
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

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("报告摘要 / 核心异常项 (选填)", systemImage: "pencil.line")
                        .font(.subheadline.weight(.semibold))
                    TextField(
                        "可简要记录您记忆中的异常（如：甲状腺结节、高血脂），或留空等待 AI 扫描解析",
                        text: $viewModel.examReportSummary,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
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
                .padding(.vertical, 12)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity)
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
    private func loadExamArchiveIfNeeded() async {
        guard let memberID = viewModel.member?.id, memberID > 0 else { return }

        if reportDetailLoader == nil {
            reportDetailLoader = MedExamDetailLazyLoadViewModel(
                reports: viewModel.memberHealthExamReports,
                medicalQueryAPI: medicalQueryAPI,
                logger: logger,
                scene: "medical_setup_exam_archive",
                onReportsUpdated: { reports in
                    viewModel.syncHealthExamReportsCache(reports)
                    flowViewModel.refreshReports(reports)
                }
            )
        }

        await viewModel.refreshMemberHealthExamReportsIfNeeded(force: true)
        flowViewModel.refreshReports(viewModel.memberHealthExamReports)
        reportDetailLoader?.replaceReports(viewModel.memberHealthExamReports)
        flowViewModel.syncMemberID(memberID)
    }

    @MainActor
    private func refreshAfterMedicalUploadSave() async {
        await viewModel.refreshMemberHealthExamReportsIfNeeded(force: true)
        flowViewModel.refreshReports(viewModel.memberHealthExamReports)
        reportDetailLoader?.replaceReports(viewModel.memberHealthExamReports)
        hasExamHistory = true
        flowViewModel.selectPath(.hasHistoryReport)
        guard let latest = viewModel.memberHealthExamReports.max(by: {
            ($0.examDate ?? .distantPast) < ($1.examDate ?? .distantPast)
        }) else { return }
        onReportSelected(latest)
    }

    @MainActor
    private func startHealthExamRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(
            files: files,
            kind: .healthExamReport,
            member: viewModel.member
        )
    }
}
