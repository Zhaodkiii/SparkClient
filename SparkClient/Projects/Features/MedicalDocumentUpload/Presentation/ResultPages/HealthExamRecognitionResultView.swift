import SwiftUI

/// 体检报告识别结果页（模块化：ResultPages/HealthExamRecognitionResult）
struct HealthExamRecognitionResultView: View {
    private let viewModel: MedicalDocumentUploadViewModel?
    private let detailContent: HealthExamRecognitionResultContentView?
    private let memberContextStore: MemberContextStore?
    private let title: String
    private let mode: HealthExamResultMode
    private let detailReportID: Int?
    private let workflowAPI: SparkMedicalWorkflowAPI?
    private let notificationClient: (any NotificationClient)?
    private let onDeleted: ((Int) -> Void)?
    private let detailShareTitle: String?
    private let detailShareMemberName: String

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var shareContext: MedicalShareContext?
    @State private var shareErrorMessage: String?
    @State private var isPreparingShare = false

    init(
        viewModel: MedicalDocumentUploadViewModel,
        memberContextStore: MemberContextStore
    ) {
        self.viewModel = viewModel
        self.detailContent = nil
        self.memberContextStore = memberContextStore
        self.title = L10n.text("medical.upload.result.health_exam.nav_title")
        self.mode = .recognition
        self.detailReportID = nil
        self.workflowAPI = nil
        self.notificationClient = nil
        self.onDeleted = nil
        self.detailShareTitle = nil
        self.detailShareMemberName = "成员"
    }

    init(
        item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        notificationClient: any NotificationClient,
        onDeleted: ((Int) -> Void)? = nil
    ) {
        self.viewModel = nil
        self.detailContent = HealthExamRecognitionResultContentView(
            item: item,
            fileTransferService: fileTransferService,
            memberContextStore: memberContextStore
        )
        self.memberContextStore = nil
        self.title = item.institutionName?.nonEmpty ?? L10n.text("home.medical.list.health_exam_reports.title")
        self.mode = .detail
        self.detailReportID = item.id
        self.workflowAPI = workflowAPI
        self.notificationClient = notificationClient
        self.onDeleted = onDeleted
        self.detailShareTitle = item.institutionName?.nonEmpty ?? L10n.text("home.medical.list.health_exam_reports.title")
        self.detailShareMemberName = "成员"
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
            .sheet(item: $shareContext) { context in
                MedicalShareSheet(context: context) {
                    shareContext = nil
                }
            }
            .alert("分享失败", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if $0 == false { shareErrorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {
                    shareErrorMessage = nil
                }
            } message: {
                Text(shareErrorMessage ?? "请稍后重试")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let detailContent {
            detailContent
        } else if let viewModel, viewModel.typedOutput != nil, let memberContextStore {
            HealthExamRecognitionResultContentView(
                viewModel: viewModel,
                memberContextStore: memberContextStore
            )
        }
    }

    @ViewBuilder
    private var toolbarActionMenu: some View {
        if mode == .detail {
            Menu {
                Button {
                    Task { await prepareShareSheet() }
                } label: {
                    Label(L10n.text("common.share", fallback: "分享"), systemImage: "square.and.arrow.up")
                }

                Button {
                } label: {
                    Label(L10n.text("common.export", fallback: "导出"), systemImage: "square.and.arrow.up.on.square")
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
                .disabled(isDeleting || isPreparingShare)
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

    @MainActor
    private func prepareShareSheet() async {
        guard isPreparingShare == false, let workflowAPI, let detailReportID else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let shareAPI = SparkMedicalShareAPI(configuration: workflowAPI.configuration)
            let response = try await shareAPI.createShare(businessType: "health_exam_report", businessID: detailReportID)
            let shareURL = AppEnvironment.current.shareWebBaseURL
                .appendingPathComponent("share")
                .appendingPathComponent(response.shareCode)
            shareContext = MedicalShareContext(
                itemTitle: detailShareTitle ?? title,
                memberName: detailShareMemberName,
                shareURL: shareURL,
                expiresAt: response.expiresAt
            )
        } catch {
            shareErrorMessage = error.localizedDescription.isEmpty ? "生成分享失败" : error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Health exam result - Light") {
    CompatibleNavigationContainer {
        HealthExamRecognitionResultView(
            viewModel: .preview(output: .previewHealthExamOutput),
            memberContextStore: MemberContextStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Health exam result - Dark") {
    CompatibleNavigationContainer {
        HealthExamRecognitionResultView(
            viewModel: .preview(output: .previewHealthExamOutput),
            memberContextStore: MemberContextStore()
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
#endif
