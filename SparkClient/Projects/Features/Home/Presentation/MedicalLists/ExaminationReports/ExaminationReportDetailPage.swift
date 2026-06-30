import SwiftUI

/// 检查报告详情页：支持服务端记录与识别结果本地草稿两种模式。
struct ExaminationReportDetailPage: View {
    let mode: ExaminationReportDetailMode
    let category: ExaminationReportCategory
    let fileTransferService: FileTransferService
    var workflowAPI: SparkMedicalWorkflowAPI?
    var completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    var notificationClient: (any NotificationClient)?
    var medicalQueryAPI: SparkMedicalQueryAPI?
    var localAttachments: [MedicalDocumentLocalAttachmentItem] = []
    let onSaved: (SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void
    let onDeleted: (Int) -> Void
    var onLocalDraftSaved: ((MedicalReportRecognitionDraft) -> Void)?
    var onLocalDraftDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    @State private var sourceReportDraft: MedicalReportRecognitionDraft?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isLoadingDetails = false
    @State private var alertMessage: String?

    init(
        mode: ExaminationReportDetailMode = .server,
        report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        category: ExaminationReportCategory,
        fileTransferService: FileTransferService,
        workflowAPI: SparkMedicalWorkflowAPI? = nil,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        memberContextStore: MemberContextStore,
        notificationClient: (any NotificationClient)? = nil,
        medicalQueryAPI: SparkMedicalQueryAPI? = nil,
        localAttachments: [MedicalDocumentLocalAttachmentItem] = [],
        sourceReportDraft: MedicalReportRecognitionDraft? = nil,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onLocalDraftSaved: ((MedicalReportRecognitionDraft) -> Void)? = nil,
        onLocalDraftDeleted: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.category = category
        self.fileTransferService = fileTransferService
        self.workflowAPI = workflowAPI
        self.completeData = completeData
        _memberContextStore = ObservedObject(wrappedValue: memberContextStore)
        self.notificationClient = notificationClient
        self.medicalQueryAPI = medicalQueryAPI
        self.localAttachments = localAttachments
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onLocalDraftSaved = onLocalDraftSaved
        self.onLocalDraftDeleted = onLocalDraftDeleted
        _report = State(initialValue: report)
        _sourceReportDraft = State(initialValue: sourceReportDraft)
    }

    private var mutationService: ExaminationReportServerMutationService? {
        workflowAPI.map { ExaminationReportServerMutationService(resources: $0) }
    }

    var body: some View {
        ExaminationReportSummaryDetailPage(
            report: $report,
            category: category,
            fileTransferService: fileTransferService,
            workflowAPI: mode == .localDraft ? nil : workflowAPI,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: mode == .localDraft ? nil : notificationClient,
            localAttachments: mode == .localDraft ? localAttachments : [],
            showsMedicalCaseLink: mode != .localDraft,
            onMedicalCaseLinked: { merged in
                report = merged
                onSaved(merged)
            },
            onMedicalCaseUpdated: nil,
            onMedicalCaseDeleted: nil
        )
        .overlay {
            if isLoadingDetails {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).opacity(0.35)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.text("home.medical.list.details.loading"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.text("common.edit"), systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label(L10n.text("common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                editSheetContent
            }
        }
        .alert(L10n.text("home.medical.examination.delete.confirm_title", fallback: "确认删除该检查报告？"), isPresented: $showingDeleteConfirm) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("common.delete"), role: .destructive) {
                Task { await deleteCurrentReport() }
            }
        } message: {
            Text(L10n.text("home.medical.examination.delete.message", fallback: "删除后无法恢复。"))
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task(id: report.id) {
            guard mode == .server else { return }
            await loadDetailsIfNeeded()
        }
    }

    @ViewBuilder
    private var editSheetContent: some View {
        switch mode {
        case .localDraft:
            ExamReportFormView(
                mode: .localEdit(existing: currentSourceReportDraft(), onSubmit: { updated in
                    applyLocalDraftReport(updated)
                    showingEditSheet = false
                })
            )
        case .server:
            if let workflowAPI {
                ExamReportFormView(
                    mode: .serverEdit(existing: report),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    onReportDraftSaved: { draft in
                        let merged = report.applyingRecognitionDraft(draft)
                        report = merged
                        onSaved(merged)
                        showingEditSheet = false
                    }
                )
            }
        }
    }

    @MainActor
    private func deleteCurrentReport() async {
        guard isDeleting == false else { return }

        if mode == .localDraft {
            onLocalDraftDeleted?()
            dismiss()
            return
        }

        guard let mutationService else {
            alertMessage = L10n.text("common.operation_failed")
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await mutationService.deleteReport(reportID: report.id)
            onDeleted(report.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func loadDetailsIfNeeded() async {
        guard report.medExamDetails == nil else { return }
        guard let medicalQueryAPI else { return }
        guard isLoadingDetails == false else { return }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            let rows = try await medicalQueryAPI.listMedExamDetails(
                memberID: report.member,
                businessType: report.medExamDetailBusinessType,
                businessID: report.id
            )
            let filtered = Self.filterMedExamRows(rows)
            var merged = report
            merged.medExamDetails = filtered
            await MainActor.run {
                report = merged
                onSaved(merged)
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func currentSourceReportDraft() -> MedicalReportRecognitionDraft {
        if let sourceReportDraft {
            return sourceReportDraft
        }
        return MedicalCaseTimelineRemoteMapping.examinationDraft(from: report)
    }

    private func applyLocalDraftReport(_ updated: MedicalReportRecognitionDraft) {
        var resolved = updated
        if resolved.attachmentFileIds.isEmpty {
            resolved.attachmentFileIds = sourceReportDraft?.attachmentFileIds ?? []
        }
        sourceReportDraft = resolved
        report = resolved.remoteExaminationReport(
            memberID: report.member,
            id: report.id,
            medicalCaseID: report.medicalRecord
        )
        onLocalDraftSaved?(resolved)
    }

    private static func filterMedExamRows(
        _ rows: [SparkMedicalSyncAPI.RemoteMedExamDetail]
    ) -> [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        let accepted = SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments.acceptedBusinessTypes
            .map { $0.lowercased() }
        let filtered = rows.filter { row in
            let normalized = row.businessType.lowercased()
            return accepted.contains(normalized) || rows.count == 1
        }
        return filtered.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
