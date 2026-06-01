import SwiftUI

/// 体检报告 / 检查报告 识别结果页面
/// 功能：展示AI识别的检查报告信息 → 支持编辑 → 保存
struct MedicalReportRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// AI 结构化提取结果
    let output: MedicalDocumentTypedExtractionOutput

    /// 报告列表（一份上传图片可能识别出多份检查报告）
    @State private var reports: [MedicalReportRecognitionDraft]
    /// 本地编辑弹窗（编辑单份报告）
    @State private var localEditor: MedicalReportResultLocalEditor?
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

        // 从识别结果中取出检查报告列表，无数据则为空数组
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
            memberID: output.envelope.memberID,
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

                // MARK: 1. 成员信息区域（报告归属的家庭成员）
                MedicalReportMemberSectionView(
                    memberID: output.envelope.memberID,
                    reports: reports
                )

                // MARK: 2. 报告统计概览区域
                MedicalReportStatsSectionView(reports: reports)

                // MARK: 3. 报告卡片列表（核心展示区）
                /// 展示所有识别出的检查报告
                /// 支持点击编辑每一份报告
                MedicalReportCardsSectionView(
                    reports: reports,
                    validationIssues: validationIssues,
                    expandedSectionIDs: $expandedValidationSections,
                    attachmentsForIDs: matchedAttachments(for:),
                    detailNavigationContext: detailNavigationContext,
                    onEdit: { index, draft in
                        logger.info("Medical report result: open local editor index=\(index)", module: logModule)
                        localEditor = .report(index: index, draft: draft) // 打开编辑页
                    },
                    onManageAttachments: { index, _ in
                        attachmentTarget = MedicalReportAttachmentTarget(index: index)
                    }
                )

                // MARK: 4. 未关联业务的源文件附件
                MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                // MARK: 5. 保存成功回执（显示记录ID）
                if let saveReceipt {
                    MedicalDocumentResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
            tintColor: Color(uiColor: .systemTeal),
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
        .background(Color(uiColor: .systemGroupedBackground))
        // 底部固定工具栏：返回 + 保存
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        // 报告数量变化时动画
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reports.count)
        // 编辑弹窗（全屏）
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
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
            // 返回按钮
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
                .buttonStyle(.bordered)

            // 保存按钮
            Button {
                logger.info("Medical report result: submit save tapped", module: logModule)
                submitSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity) // 保存中显示加载动画
                    } else {
                        Text(L10n.text("medical.upload.result.common.submit")).frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving) // 保存中禁用按钮
        }
    }

    private func submitSave() {
        viewModel.updateTypedResult(.medicalReport(reports))
        Task { _ = await viewModel.saveResult() }
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in reports.indices where index != targetIndex {
            reports[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
    }

    // MARK: - 编辑页面路由
    /// 跳转到检查报告编辑页面
    @ViewBuilder
    private func editorDestination(_ editor: MedicalReportResultLocalEditor) -> some View {
        switch editor {
        case .report(let index, let draft):
            ExamReportFormView(
                mode: .localEdit(existing: draft, onSubmit: { updated in
                    // 保存编辑后的报告数据
                    guard reports.indices.contains(index) else { return }
                    reports[index] = updated
                    logger.info("Medical report result: local report updated index=\(index)", module: logModule)
                })
            )
        }
    }
}
