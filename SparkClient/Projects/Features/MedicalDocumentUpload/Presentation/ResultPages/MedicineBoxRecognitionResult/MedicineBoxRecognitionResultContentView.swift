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
    @State private var attachmentTarget: MedicineBoxAttachmentTarget?
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
                        onUpdateMedicineBoxDraft: updateMedicineBoxDraft(at:draft:),
                        onDeleteMedicineBoxDraft: deleteMedicineBoxDraft(at:),
                        onManageAttachments: { index in
                            attachmentTarget = MedicineBoxAttachmentTarget(index: index)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: items.count)
        .onChange(of: items) { newValue in
            syncItemsToViewModel(newValue)
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: attachments,
                selectedIDs: items.indices.contains(target.index) ? items[target.index].attachmentFileIds : [],
                onSubmit: { ids in
                    guard items.indices.contains(target.index) else { return }
                    removeAttachmentIDs(ids, except: target.index)
                    items[target.index].attachmentFileIds = ids
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
                logger.info("Medicine box result: submit save tapped items=\(items.count)", module: logModule)
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
            .disabled(isSaving || items.isEmpty)
        }
    }

    private func submitSave() {
        syncItemsToViewModel(items)
        Task { _ = await viewModel.saveResult() }
    }

    private func syncItemsToViewModel(_ boxes: [MedicineBoxRecognitionDraft]) {
        viewModel.updateTypedResult(.medicineBoxes(boxes))
    }

    private func updateMedicineBoxDraft(at index: Int, draft: MedicineBoxRecognitionDraft) {
        guard items.indices.contains(index) else { return }
        var resolved = draft
        if resolved.sortOrder?.nilIfBlank == nil {
            resolved.sortOrder = items[index].sortOrder
        }
        if resolved.attachmentFileIds.isEmpty {
            resolved.attachmentFileIds = items[index].attachmentFileIds
        }
        items[index] = resolved
        logger.info("Medicine box result: local item updated index=\(index)", module: logModule)
    }

    private func deleteMedicineBoxDraft(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        logger.info("Medicine box result: local item deleted index=\(index)", module: logModule)
    }

    private func removeAttachmentIDs(_ ids: [UUID], except targetIndex: Int) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for index in items.indices where index != targetIndex {
            items[index].attachmentFileIds.removeAll { idSet.contains($0) }
        }
    }
}
