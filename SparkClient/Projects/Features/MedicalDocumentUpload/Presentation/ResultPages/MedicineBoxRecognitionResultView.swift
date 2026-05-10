import SwiftUI

struct MedicineBoxRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onUpdate: (MedicalDocumentTypedResult) -> Void
    let onSave: () -> Void

    @State private var items: [MedicineBoxRecognitionDraft]
    @State private var editingItem: MedicineBoxRecognitionEditor?

    init(
        output: MedicalDocumentTypedExtractionOutput,
        isSaving: Bool,
        saveReceipt: MedicalDocumentSaveReceipt?,
        onBack: @escaping () -> Void,
        onUpdate: @escaping (MedicalDocumentTypedResult) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.output = output
        self.isSaving = isSaving
        self.saveReceipt = saveReceipt
        self.onBack = onBack
        self.onUpdate = onUpdate
        self.onSave = onSave
        if case .medicineBoxes(let boxes) = output.typedResult {
            _items = State(initialValue: boxes)
        } else {
            _items = State(initialValue: [])
        }
    }

    private var attachments: [MedicationResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicationResultLocalAttachmentItem(file: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MedicationResultSectionCard(
                    title: L10n.text("medical.upload.result.medicine_box.member.title", fallback: "确认成员"),
                    subtitle: L10n.text("medical.upload.result.medicine_box.member.subtitle", fallback: "保存后会加入该成员的药箱"),
                    systemImage: "person.crop.circle.badge.checkmark"
                ) {
                    MedicationResultInfoLine(
                        title: L10n.text("medical.upload.result.member.id"),
                        value: output.envelope.memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                    )
                    MedicationResultInfoLine(
                        title: L10n.text("medical.upload.result.medicine_box.total_count", fallback: "药品数量"),
                        value: "\(items.count)"
                    )
                }

                MedicationResultSectionCard(
                    title: L10n.text("medical.upload.result.medicine_box.section.title", fallback: "药箱药品"),
                    subtitle: L10n.text("medical.upload.result.medicine_box.section.subtitle", fallback: "可逐条编辑识别结果后保存"),
                    systemImage: "shippingbox.fill",
                    badgeText: String(format: L10n.text("medical.upload.result.medication.count_format"), locale: .current, items.count)
                ) {
                    if items.isEmpty {
                        Text(L10n.text("medical.upload.result.medicine_box.empty", fallback: "暂无药品"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                                itemRow(index: pair.offset, item: pair.element)
                            }
                        }
                    }
                }

                MedicationAttachmentsSectionView(attachments: attachments)

                if let saveReceipt {
                    MedicationResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        MedicationResultInfoLine(
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
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .fullScreenCover(item: $editingItem) { editor in
            MedicineBoxFormView(
                mode: .localEdit(existing: MedicineBoxDraft(recognition: editor.item), onSubmit: { draft in
                    guard items.indices.contains(editor.index) else { return }
                    items[editor.index] = draft.recognitionDraft(sortOrder: editor.item.sortOrder)
                    onUpdate(.medicineBoxes(items))
                }),
                memberID: output.envelope.memberID ?? 0,
                workflowAPI: AppContainer.preview.backend.medicalWorkflow
            )
        }
        .onChange(of: items) { newValue in
            onUpdate(.medicineBoxes(newValue))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back"), action: onBack)
                .buttonStyle(.bordered)

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
            .disabled(isSaving || items.isEmpty)
        }
    }

    private func itemRow(index: Int, item: MedicineBoxRecognitionDraft) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .systemPurple))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.medicineName?.nilIfBlank ?? L10n.text("medical.upload.result.medication.unnamed"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                let detail = [item.strength, item.dosageForm, item.expireDate]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: " · ")
                if detail.isEmpty == false {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(L10n.text("common.edit")) {
                editingItem = MedicineBoxRecognitionEditor(index: index, item: item)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct MedicineBoxRecognitionEditor: Identifiable {
    let index: Int
    let item: MedicineBoxRecognitionDraft

    var id: String { "medicine-box-\(index)" }
}
