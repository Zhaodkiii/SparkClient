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
    var archiveMode: MedicalArchiveListMode = .active

    @State private var rows: [SparkMedicalSyncAPI.RemoteMedicalCaseSummary]
    @State private var showingCreateSheet = false
    /// 本页拍照上传 Sheet 与 OCR 识别流程共用的文档类型（须保持一致）。
    private static let uploadDocumentKind: MedicalDocumentKind = .caseDocument

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
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil,
        archiveMode: MedicalArchiveListMode = .active
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
        self.archiveMode = archiveMode
        _rows = State(initialValue: archiveMode == .active ? (completeData?.medicalCases ?? []) : [])
    }

    private var navigationTitleText: String {
        archiveMode == .archived
            ? L10n.text("medical.archive.list.medical_cases.title")
            : L10n.text("home.medical.list.medical_cases.title")
    }

    var body: some View {
        ScrollView {
            if rows.isEmpty {
                if archiveMode == .archived {
                    Text(L10n.text("medical.archive.list.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    MedicalListEmptyRow()
                }
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
                        onDeleted: removeCase,
                        onArchiveStateChanged: handleArchiveStateChanged,
                        archiveMode: archiveMode
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
        .navigationTitle(navigationTitleText)
        .toolbar {
            if archiveMode == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    MainNavigationLink {
                        MedicalCasesListPage(
                            completeData: completeData,
                            workflowAPI: workflowAPI,
                            medicalQueryAPI: medicalQueryAPI,
                            fileTransferService: fileTransferService,
                            memberContextStore: memberContextStore,
                            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                            aiSettingsViewModel: aiSettingsViewModel,
                            notificationClient: notificationClient,
                            logger: logger,
                            onCasesUpdated: nil,
                            onExaminationReportsUpdated: onExaminationReportsUpdated,
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
                    isEnabled: defaultMemberID > 0,
                    onManualAdd: { showingCreateSheet = true },
                    onUploadConfirmed: { files in startCaseDocumentRecognition(files: files) }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)

        .onChange(of: completeData?.medicalCases ?? []) { newValue in
            guard archiveMode == .active else { return }
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
        .task(id: archiveMode == .archived) {
            if archiveMode == .archived {
                await refreshCases()
            }
        }
    }

    private var defaultMemberID: Int {
        completeData?.member.id ?? memberContextStore.context.selectedMember?.id ?? 0
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
        if archiveMode == .active {
            onCasesUpdated?(rows)
        }
    }

    private func removeCase(_ id: Int) {
        rows.removeAll { $0.id == id }
        if archiveMode == .active {
            onCasesUpdated?(rows)
        }
    }

    private func handleArchiveStateChanged(id: Int, isArchived: Bool) {
        let belongsInList = archiveMode == .archived ? isArchived : !isArchived
        if belongsInList == false {
            removeCase(id)
        }
    }

    @MainActor
    private func startCaseDocumentRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: Self.uploadDocumentKind)
    }

    @MainActor
    private func refreshCases() async {
        guard let memberID = refreshMemberID else {
            logger.warning("病历列表下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("病历列表下拉刷新开始 memberID=\(memberID) archiveMode=\(archiveMode)", module: .home)

        do {
            let refreshedRows = try await medicalQueryAPI.listMedicalCaseSummaries(
                memberID: memberID,
                archived: archiveMode.query
            )
            rows = refreshedRows
            if archiveMode == .active {
                onCasesUpdated?(refreshedRows)
            }
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
