import SwiftUI

/// 病例记录列表页。
struct MedicalCasesListPage: View {
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let notificationClient: any NotificationClient
    let logger: Logger
    let onCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    let onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)?

    @State private var rows: [SparkMedicalSyncAPI.RemoteMedicalCaseSummary]
    @State private var showingCreateSheet = false
    @State private var showingUploadSheet = false

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        notificationClient: any NotificationClient,
        logger: Logger,
        onCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?,
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.medicalQueryAPI = medicalQueryAPI
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.notificationClient = notificationClient
        self.logger = logger
        self.onCasesUpdated = onCasesUpdated
        self.onExaminationReportsUpdated = onExaminationReportsUpdated
        _rows = State(initialValue: completeData?.medicalCases ?? [])
    }

    var body: some View {
        List {
            if rows.isEmpty {
                MedicalListEmptyRow()
            } else {
                ForEach(rows, id: \.id) { item in
                    MedicalRecordCard(
                        item: item,
                        completeData: completeData,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient,
                        logger: logger,
                        onExaminationReportsUpdated: onExaminationReportsUpdated,
                        onUpdated: upsertCase,
                        onDeleted: removeCase
                    )
                        .medicalListCardRowStyle()
                }
            }
        }
        .refreshable {
            await refreshCases()
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medical_cases.title"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .onChange(of: completeData?.medicalCases ?? []) { newValue in
            rows = newValue
        }
        .sheet(isPresented: $showingCreateSheet) {
            CompatibleNavigationContainer {
                MedicalCaseFormView(
                    mode: .create(memberID: defaultMemberID, onSaved: upsertCase),
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    notificationClient: notificationClient
                )
            }
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicineBoxUploadSheet(
                title: L10n.text("medical.upload.case_document.sheet.title", fallback: "选择病历图片"),
                headerTitle: L10n.text("medical.upload.case_document.sheet.header", fallback: "选择上传方式"),
                headerSubtitle: L10n.text("medical.upload.case_document.sheet.subtitle", fallback: "可一次选择最多 5 个门诊病历、出院小结或相关附件，确认后开始识别。"),
                emptyTitle: L10n.text("medical.upload.case_document.sheet.empty.title", fallback: "尚未选择文件"),
                emptySubtitle: L10n.text("medical.upload.case_document.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片"),
                fileNamePrefix: "case_document",
                maxFileCount: 5
            ) { files in
                startCaseDocumentRecognition(files: files)
            }
        }
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
            }
        }
    }

    private var defaultMemberID: Int {
        completeData?.member.id ?? memberContextStore.context.selectedMember?.id ?? 0
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(uiColor: .separator).opacity(0.2))

            VStack(spacing: 12) {
                GeometryReader { proxy in
                    HStack(spacing: 12) {
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label(L10n.text("home.medical.list.medical_cases.action.manual_add", fallback: "手动添加"), systemImage: "plus")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemBlue))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    Color(uiColor: .systemBlue).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(uiColor: .systemBlue).opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(defaultMemberID <= 0)
                        .frame(width: max(112, proxy.size.width * 0.34))

                        Button {
                            showingUploadSheet = true
                        } label: {
                            Label(L10n.text("home.medical.list.medical_cases.action.camera_add_case", fallback: "拍摄添加病历"), systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    Color(uiColor: .systemBlue),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(defaultMemberID <= 0)
                    }
                }
                .frame(height: 52)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var refreshMemberID: Int? {
        completeData?.memberId ?? memberContextStore.context.selectedMember?.id
    }

    private func upsertCase(_ item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        if let index = rows.firstIndex(where: { $0.id == item.id }) {
            rows[index] = item
        } else {
            rows.insert(item, at: 0)
        }
        onCasesUpdated?(rows)
    }

    private func removeCase(_ id: Int) {
        rows.removeAll { $0.id == id }
        onCasesUpdated?(rows)
    }

    @MainActor
    private func startCaseDocumentRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .caseDocument)
    }

    @MainActor
    private func refreshCases() async {
        guard let memberID = refreshMemberID else {
            logger.warning("病历列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("病历列表下拉刷新开始 memberID=\(memberID)", module: .home)

        do {
            // 下拉刷新只拉取病历列表，并只回写首页 completeData.medicalCases 缓存字段。
            let refreshedRows = try await medicalQueryAPI.listMedicalCaseSummaries(memberID: memberID)
            rows = refreshedRows
            onCasesUpdated?(refreshedRows)
            logger.info(
                "病历列表下拉刷新完成 memberID=\(memberID) count=\(refreshedRows.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
                module: .home
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.medical_cases.refresh")
            logger.warning("病历列表下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: .home)
        }
    }
}
