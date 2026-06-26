import SwiftUI

/// 体检报告 / 检查报告 识别结果页面
/// 功能：展示AI识别的检查报告信息 → 支持编辑 → 保存
struct MedicalReportRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 当前选中的家庭成员 ID，用于保存归属
    @State private var selectedMemberID: Int?
    /// 报告列表（一份上传图片可能识别出多份检查报告）
    @State private var reports: [MedicalReportRecognitionDraft]
    @State private var attachmentTarget: MedicalReportAttachmentTarget?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?
    /// 日志工具
    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    /// 初始化：从 AI 输出中提取检查报告数据
    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output
        _selectedMemberID = State(initialValue: output.envelope.memberID)

        if case .medicalReport(let drafts) = output.typedResult {
            _reports = State(initialValue: drafts)
        } else {
            _reports = State(initialValue: [])
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }
    private var validationIssues: [MedicalPreSubmitValidationIssue] { viewModel.preSubmitValidationIssues }
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: selectedMemberID,
            viewModel: viewModel,
            logger: logger
        )
    }

    /// 附件（上传的检查报告照片）
    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(reports.associatedAttachmentFileIDs)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedicalPreSubmitValidationSummaryBanner(issues: validationIssues) { issue in
                        MedicalPreSubmitValidationNavigation.reveal(
                            issue: issue,
                            expandedSectionIDs: $expandedValidationSections,
                            scrollProxy: scrollProxy
                        )
                    }

                    MedicalReportMemberConfirmSectionView(
                        memberContextStore: viewModel.memberContextStoreForLocalForms,
                        selectedMemberID: selectedMemberID,
                        reports: reports,
                        onSelectMember: { memberID in
                            selectedMemberID = memberID
                            viewModel.updateResultMemberID(memberID)
                        }
                    )

                    MedicalReportCardsSectionView(
                        reports: reports,
                        validationIssues: validationIssues,
                        attachmentsForIDs: matchedAttachments(for:),
                        detailNavigationContext: detailNavigationContext,
                        onUpdateReportDraft: updateReportDraft(at:draft:),
                        onDeleteReportDraft: deleteReportDraft(at:),
                        onManageAttachments: { index in
                            attachmentTarget = MedicalReportAttachmentTarget(index: index)
                        }
                    )

                    MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                    if let saveReceipt {
                        MedicalDocumentResultSectionCard(
                            title: L10n.text("medical.upload.result.common.save_status"),
                            subtitle: L10n.text("medical.upload.result.common.save_success"),
                            systemImage: "checkmark.circle",
                            badgeText: L10n.text("medical.upload.result.common.saved")
                        ) {
                            MedicalDocumentResultInfoLine(
                                title: L10n.text("medical.upload.result.common.record_id"),
                                value: "\(saveReceipt.recordID)"
                            )
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: validationIssues.map(\.id)) { _ in
                MedicalPreSubmitValidationNavigation.autoRevealFirstBlockingIssueIfNeeded(
                    issues: validationIssues,
                    lastAutoRevealedIssueID: &lastAutoRevealedIssueID,
                    expandedSectionIDs: $expandedValidationSections,
                    scrollProxy: scrollProxy
                )
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reports.count)
        .onChange(of: reports) { newValue in
            syncReportsToViewModel(newValue)
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: attachments,
                selectedIDs: reports.indices.contains(target.index) ? reports[target.index].attachmentFileIds : [],
                onSubmit: { ids in
                    guard reports.indices.contains(target.index) else { return }
                    removeAttachmentIDs(ids, except: target.index)
                    reports[target.index].attachmentFileIds = ids
                }
            )
        }
    }

    // MARK: - 底部工具栏
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
            .buttonStyle(.bordered)

            Button {
                logger.info("Medical report result: submit save tapped reports=\(reports.count)", module: logModule)
                submitSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("medical.upload.result.common.submit")).frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || reports.isEmpty)
        }
    }

    private func submitSave() {
        syncReportsToViewModel(reports)
        Task { _ = await viewModel.saveResult() }
    }

    private func syncReportsToViewModel(_ drafts: [MedicalReportRecognitionDraft]) {
        viewModel.updateTypedResult(.medicalReport(drafts))
    }

    private func updateReportDraft(at index: Int, draft: MedicalReportRecognitionDraft) {
        guard reports.indices.contains(index) else { return }
        var resolved = draft
        if resolved.attachmentFileIds.isEmpty {
            resolved.attachmentFileIds = reports[index].attachmentFileIds
        }
        reports[index] = resolved
        logger.info("Medical report result: local item updated index=\(index)", module: logModule)
    }

    private func deleteReportDraft(at index: Int) {
        guard reports.indices.contains(index) else { return }
        reports.remove(at: index)
        logger.info("Medical report result: local item deleted index=\(index)", module: logModule)
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in reports.indices where index != targetIndex {
            reports[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
    }
}
