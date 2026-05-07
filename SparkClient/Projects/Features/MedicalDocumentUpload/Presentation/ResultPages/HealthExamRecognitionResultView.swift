import SwiftUI

/// 体检报告识别结果页（模块化：ResultPages/HealthExamRecognitionResult）
struct HealthExamRecognitionResultView: View {
    private let content: HealthExamRecognitionResultContentView
    private let title: String
    private let mode: HealthExamResultMode
    private let detailReportID: Int?
    private let workflowAPI: SparkMedicalWorkflowAPI?
    private let notificationClient: (any NotificationClient)?
    private let onDeleted: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirm = false
    @State private var isDeleting = false

    init(
        output: MedicalDocumentTypedExtractionOutput,
        memberContextStore: MemberContextStore,
        isSaving: Bool,
        saveReceipt: MedicalDocumentSaveReceipt?,
        onBack: @escaping () -> Void,
        onSelectMember: @escaping (Int?) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.content = HealthExamRecognitionResultContentView(
            output: output,
            memberContextStore: memberContextStore,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSelectMember: onSelectMember,
            onSave: onSave
        )
        self.title = L10n.text("medical.upload.result.health_exam.nav_title")
        self.mode = .recognition
        self.detailReportID = nil
        self.workflowAPI = nil
        self.notificationClient = nil
        self.onDeleted = nil
    }

    init(
        item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        notificationClient: any NotificationClient,
        onDeleted: ((Int) -> Void)? = nil
    ) {
        self.content = HealthExamRecognitionResultContentView(
            item: item,
            fileTransferService: fileTransferService,
            memberContextStore: memberContextStore
        )
        self.title = item.institutionName?.nonEmpty ?? L10n.text("home.medical.list.health_exam_reports.title")
        self.mode = .detail
        self.detailReportID = item.id
        self.workflowAPI = workflowAPI
        self.notificationClient = notificationClient
        self.onDeleted = onDeleted
    }

    var body: some View {
        content
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarActionMenu
            }
        }
        .alert(
            L10n.text("home.medical.list.health_exam.delete.confirm_title", fallback: "删除体检报告？"),
            isPresented: $isShowingDeleteConfirm
        ) {
            Button(L10n.text("common.delete"), role: .destructive) {
                Task { await deleteDetailReport() }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("home.medical.list.health_exam.delete.confirm_message", fallback: "删除后该报告将从列表中移除。"))
        }
    }

    @ViewBuilder
    private var toolbarActionMenu: some View {
        if mode == .detail {
            Menu {
                Button {
                } label: {
                    Label(L10n.text("common.export", fallback: "导出"), systemImage: "square.and.arrow.up.on.square")
                }

                Button {
                } label: {
                    Label(L10n.text("common.share", fallback: "分享"), systemImage: "square.and.arrow.up")
                }

                Button {
                } label: {
                    Label(L10n.text("common.edit"), systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    isShowingDeleteConfirm = true
                } label: {
                    Label(L10n.text("common.delete"), systemImage: "trash")
                }
                .disabled(isDeleting)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        } else {
            EmptyView()
        }
    }

    @MainActor
    private func deleteDetailReport() async {
        guard isDeleting == false, let detailReportID, let workflowAPI else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .healthExamReports, id: detailReportID)
            notificationClient?.success(L10n.text("home.medical.list.health_exam.delete.success", fallback: "体检报告已删除"), source: "health.exam.detail")
            onDeleted?(detailReportID)
            dismiss()
        } catch {
            notificationClient?.error(error.localizedDescription, title: L10n.text("home.medical.list.health_exam.delete.failed", fallback: "删除失败"), source: "health.exam.detail")
        }
    }
}

#Preview("Health exam result - Light") {
    CompatibleNavigationContainer {
        HealthExamRecognitionResultView(
            output: .previewHealthExamOutput,
            memberContextStore: MemberContextStore(),
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSelectMember: { _ in },
            onSave: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Health exam result - Dark") {
    CompatibleNavigationContainer {
        HealthExamRecognitionResultView(
            output: .previewHealthExamOutput,
            memberContextStore: MemberContextStore(),
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSelectMember: { _ in },
            onSave: {}
        )
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewHealthExamOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 9,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/health-exam.pdf"),
                        displayName: "年度体检报告.pdf",
                        mimeType: "application/pdf"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .healthExamReport,
                    confidence: 0.95,
                    source: .ai,
                    reason: "命中体检报告字段"
                )
            ),
            typedResult: .healthExamReport(
                HealthExamRecognitionDraft(
                    institutionName: "仁和医院体检中心",
                    reportNo: "HE-2026-001",
                    examDate: "2026-04-12",
                    examType: "年度体检",
                    summary: "血脂略高，建议控制饮食并复查。",
                    items: [
                        MedicalReportItem(
                            category: "血常规",
                            subCategory: nil,
                            itemName: "白细胞计数",
                            itemCode: "WBC",
                            resultValue: "11.2",
                            unit: "10^9/L",
                            referenceRange: "3.5-9.5",
                            flag: "high",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: nil,
                            diagnosis: nil,
                            extra: nil,
                            sortOrder: "1"
                        ),
                        MedicalReportItem(
                            category: "影像",
                            subCategory: "胸部CT",
                            itemName: "胸部CT平扫",
                            itemCode: "CT",
                            resultValue: "轻度纹理增多",
                            unit: nil,
                            referenceRange: nil,
                            flag: "abnormal",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: "胸部",
                            diagnosis: "建议随访",
                            extra: nil,
                            sortOrder: "2"
                        ),
                        MedicalReportItem(
                            category: "尿常规",
                            subCategory: nil,
                            itemName: "尿蛋白",
                            itemCode: "PRO",
                            resultValue: "阴性",
                            unit: nil,
                            referenceRange: "阴性",
                            flag: "normal",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: nil,
                            diagnosis: nil,
                            extra: nil,
                            sortOrder: "3"
                        )
                    ]
                )
            ),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
