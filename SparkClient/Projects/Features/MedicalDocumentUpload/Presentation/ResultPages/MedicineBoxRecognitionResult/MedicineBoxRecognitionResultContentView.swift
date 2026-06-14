import SwiftUI

/// 药箱识别结果页面
/// 功能：展示AI识别的药品信息 → 支持编辑 → 保存到个人药箱
struct MedicineBoxRecognitionResultContentView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// 医疗文档结构化提取输出（AI识别的原始结果）
    let output: MedicalDocumentTypedExtractionOutput

    /// 当前选中的家庭成员 ID，用于保存归属
    @State private var selectedMemberID: Int?
    /// 药品列表草稿数据（可编辑）
    @State private var items: [MedicineBoxRecognitionDraft]
    @State private var activeSheet: MedicineBoxRecognitionSheet?
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?

    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output
        _selectedMemberID = State(initialValue: output.envelope.memberID)

        if case .medicineBoxes(let boxes) = output.typedResult {
            _items = State(initialValue: boxes)
        } else {
            _items = State(initialValue: [])
        }
    }

    /// 附件列表（上传的药盒照片/OCR文件）
    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(items.associatedAttachmentFileIDs)
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

    private func onBack() {
        viewModel.reset(keepAttachments: true)
    }

    private func onUpdate(_ typedResult: MedicalDocumentTypedResult) {
        viewModel.updateTypedResult(typedResult)
    }

    private func onSave() {
        Task { _ = await viewModel.saveResult() }
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in items.indices where index != targetIndex {
            items[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
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

                MedicineBoxMemberConfirmSectionView(
                    memberContextStore: viewModel.memberContextStoreForLocalForms,
                    selectedMemberID: selectedMemberID,
                    medicineCount: items.count,
                    onSelectMember: { memberID in
                        selectedMemberID = memberID
                        viewModel.updateResultMemberID(memberID)
                    }
                )

                MedicineBoxListSectionView(
                    items: items,
                    validationIssues: validationIssues,
                    attachmentsForIDs: matchedAttachments(for:),
                    detailNavigationContext: detailNavigationContext,
                    onLocalDraftSaved: applyLocalDraftSaved(index:updated:),
                    onLocalDraftDeleted: applyLocalDraftDeleted(index:),
                    onEdit: { index, item in
                        activeSheet = .edit(MedicineBoxRecognitionEditor(index: index, item: item))
                    },
                    onManageAttachments: { index in
                        activeSheet = .attachments(MedicineBoxAttachmentTarget(index: index))
                    }
                )

                // MARK: - 未关联业务的源文件附件
                MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                // MARK: - 保存成功回执区域
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
        // 底部固定操作栏
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let editor):
                MedicineBoxFormView(
                    mode: .localEdit(existing: MedicineBoxDraft(recognition: editor.item), onSubmit: { draft in
                        guard items.indices.contains(editor.index) else { return }
                        items[editor.index] = draft.recognitionDraft(sortOrder: editor.item.sortOrder)
                        onUpdate(.medicineBoxes(items))
                    }),
                    entryMemberID: selectedMemberID ?? 0,
                    workflowAPI: AppContainer.preview.backend.medicalWorkflow
                )
            case .attachments(let target):
                MedicalDocumentAttachmentAssociationSheet(
                    title: target.title,
                    localAttachments: attachments,
                    selectedIDs: items.indices.contains(target.index) ? items[target.index].attachmentFileIds : [],
                    onSubmit: { ids in
                        guard items.indices.contains(target.index) else { return }
                        removeAttachmentIDs(ids, except: target.index)
                        items[target.index].attachmentFileIds = ids
                        onUpdate(.medicineBoxes(items))
                    }
                )
            }
        }
        // 监听药品列表变化，自动通知上层更新
        .onChange(of: items) { newValue in
            onUpdate(.medicineBoxes(newValue))
        }
    }

    private func applyLocalDraftSaved(index: Int, updated: MedicineBoxRecognitionDraft) {
        guard items.indices.contains(index) else { return }
        var draft = updated
        if draft.sortOrder?.nilIfBlank == nil {
            draft.sortOrder = items[index].sortOrder
        }
        if draft.attachmentFileIds.isEmpty {
            draft.attachmentFileIds = items[index].attachmentFileIds
        }
        items[index] = draft
        logger.info("Medicine box result: local draft saved index=\(index)", module: logModule)
        onUpdate(.medicineBoxes(items))
    }

    private func applyLocalDraftDeleted(index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        logger.info("Medicine box result: local draft deleted index=\(index)", module: logModule)
        onUpdate(.medicineBoxes(items))
    }

    // MARK: - 底部工具栏（返回 + 保存）
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 返回按钮
            Button(L10n.text("medical.upload.result.common.back"), action: onBack)
                .buttonStyle(.bordered)

            // 保存按钮
            Button {
                onUpdate(.medicineBoxes(items))
                onSave()
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
            .disabled(isSaving || items.isEmpty) // 保存中/无药品 时禁用
        }
    }
}
