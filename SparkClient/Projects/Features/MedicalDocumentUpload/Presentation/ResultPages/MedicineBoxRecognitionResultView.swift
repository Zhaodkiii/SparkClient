import SwiftUI

/// 药盒识别结果页面
/// 功能：展示AI识别的药品信息 → 支持编辑 → 保存到个人药箱
struct MedicineBoxRecognitionResultView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// 医疗文档结构化提取输出（AI识别的原始结果）
    let output: MedicalDocumentTypedExtractionOutput

    /// 药品列表草稿数据（可编辑）
    @State private var items: [MedicineBoxRecognitionDraft]
    /// 当前正在编辑的药品项（弹出编辑页）
    @State private var editingItem: MedicineBoxRecognitionEditor?
    @State private var attachmentTarget: MedicineBoxAttachmentTarget?

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.output = output

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - 成员信息区域
                MedicalDocumentResultSectionCard(
                    title: L10n.text("medical.upload.result.medicine_box.member.title", fallback: "确认成员"),
                    subtitle: L10n.text("medical.upload.result.medicine_box.member.subtitle", fallback: "保存后会加入该成员的药箱"),
                    systemImage: "person.crop.circle.badge.checkmark",
            tintColor: Color(uiColor: .systemTeal)
                ) {
                    // 成员ID
                    MedicalDocumentResultInfoLine(
                        title: L10n.text("medical.upload.result.member.id"),
                        value: output.envelope.memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                    )
                    // 药品总数量
                    MedicalDocumentResultInfoLine(
                        title: L10n.text("medical.upload.result.medicine_box.total_count", fallback: "药品数量"),
                        value: "\(items.count)"
                    )
                }

                // MARK: - 药品列表区域
                MedicalDocumentResultSectionCard(
                    title: L10n.text("medical.upload.result.medicine_box.section.title", fallback: "药箱药品"),
                    subtitle: L10n.text("medical.upload.result.medicine_box.section.subtitle", fallback: "可逐条编辑识别结果后保存"),
                    systemImage: "shippingbox.fill",
            tintColor: Color(uiColor: .systemTeal),
                    badgeText: String(format: L10n.text("medical.upload.result.medication.count_format"), locale: .current, items.count)
                ) {
                    if items.isEmpty {
                        // 无药品时展示空状态
                        Text(L10n.text("medical.upload.result.medicine_box.empty", fallback: "暂无药品"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            // 遍历展示所有药品
                            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                                itemRow(index: pair.offset, item: pair.element)
                            }
                        }
                    }
                }

                // MARK: - 未关联业务的源文件附件
                MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                // MARK: - 保存成功回执区域
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medicine_box.title", fallback: "药箱"))
        .navigationBarTitleDisplayMode(.inline)
        // 底部固定操作栏
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        // 弹出药品编辑页面
        .fullScreenCover(item: $editingItem) { editor in
            MedicineBoxFormView(
                mode: .localEdit(existing: MedicineBoxDraft(recognition: editor.item), onSubmit: { draft in
                    guard items.indices.contains(editor.index) else { return }
                    // 保存编辑后的药品信息
                    items[editor.index] = draft.recognitionDraft(sortOrder: editor.item.sortOrder)
                    onUpdate(.medicineBoxes(items))
                }),
                memberID: output.envelope.memberID ?? 0,
                workflowAPI: AppContainer.preview.backend.medicalWorkflow
            )
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
                    onUpdate(.medicineBoxes(items))
                }
            )
        }
        // 监听药品列表变化，自动通知上层更新
        .onChange(of: items) { newValue in
            onUpdate(.medicineBoxes(newValue))
        }
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

    // MARK: - 单行药品条目
    /// 展示单个药品信息 + 编辑按钮
    private func itemRow(index: Int, item: MedicineBoxRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // 药品图标
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemPurple))

                VStack(alignment: .leading, spacing: 4) {
                    // 药品名称
                    Text(item.medicineName?.nilIfBlank ?? L10n.text("medical.upload.result.medication.unnamed"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    // 药品详情：规格 + 剂型 + 有效期
                    let detail = [item.strength, item.dosageForm, item.expireDate]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 编辑按钮
                Button(L10n.text("common.edit")) {
                    editingItem = MedicineBoxRecognitionEditor(index: index, item: item)
                }
                .font(.caption.weight(.semibold))
            }

            CaseMatchedAttachmentsGridView(
                title: "药品附件",
                attachments: matchedAttachments(for: item.attachmentFileIds),
                onManage: {
                    attachmentTarget = MedicineBoxAttachmentTarget(index: index)
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - 药品编辑对象（用于弹窗标识）
/// 标识当前正在编辑的药品索引和数据
private struct MedicineBoxRecognitionEditor: Identifiable {
    let index: Int          // 药品在列表中的下标
    let item: MedicineBoxRecognitionDraft  // 药品数据

    var id: String { "medicine-box-\(index)" }
}

private struct MedicineBoxAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medicine-box-attachment-\(index)" }
    var title: String { "关联药品附件" }
}
