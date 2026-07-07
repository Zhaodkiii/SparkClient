import SwiftUI

struct MedicineBoxDetailPage: View {
    let mode: MedicineBoxDetailMode
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let entryMemberID: Int?
    let memberOptions: [Member]
    let allowsHouseholdPublic: Bool
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onDeleted: (Int) -> Void
    var onLocalDraftSaved: ((MedicineBoxRecognitionDraft) -> Void)?
    var onLocalDraftDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentBox: SparkMedicalSyncAPI.RemoteMedicineBox
    @State private var sourceBoxDraft: MedicineBoxRecognitionDraft?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var isDeleting = false
    @State private var isEditingAttachments = false
    @State private var attachmentsDirty = false
    @State private var shareContext: MedicalShareContext?
    @State private var shareErrorMessage: String?
    @State private var isPreparingShare = false

    init(
        mode: MedicineBoxDetailMode = .server,
        box: SparkMedicalSyncAPI.RemoteMedicineBox,
        entryMemberID: Int? = nil,
        memberOptions: [Member] = [],
        allowsHouseholdPublic: Bool = false,
        typeOptions: [String],
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        sourceBoxDraft: MedicineBoxRecognitionDraft? = nil,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onLocalDraftSaved: ((MedicineBoxRecognitionDraft) -> Void)? = nil,
        onLocalDraftDeleted: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.box = box
        self.entryMemberID = entryMemberID
        self.memberOptions = memberOptions
        self.allowsHouseholdPublic = allowsHouseholdPublic
        self.typeOptions = typeOptions
        self.specOptionBoxes = specOptionBoxes
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onLocalDraftSaved = onLocalDraftSaved
        self.onLocalDraftDeleted = onLocalDraftDeleted
        _currentBox = State(initialValue: box)
        _sourceBoxDraft = State(initialValue: sourceBoxDraft)
    }

    private var resolvedEntryMemberID: Int {
        entryMemberID ?? box.member ?? memberOptions.first?.id ?? 0
    }

    private var ownershipDisplay: String {
        guard let memberID = currentBox.member else {
            return L10n.text("home.medical.medicine_box.ownership.household")
        }
        return memberOptions.first(where: { $0.id == memberID })?.name
            ?? L10n.text("home.medical.medicine_box.ownership.member_fallback")
    }

    var body: some View {
        List {
            if allowsHouseholdPublic {
                Section(L10n.text("home.medical.medicine_box.section.ownership")) {
                    MedicineBoxDetailRow(
                        title: L10n.text("home.medical.medicine_box.field.binding_member"),
                        value: ownershipDisplay
                    )
                }
            }

            Section(L10n.text("home.medical.medicine_box.section.info")) {
                MedicineBoxDetailRow(title: L10n.text("home.medical.medicine_box.field.medicine_name"), value: currentBox.medicineName)
                MedicineBoxDetailRow(title: L10n.text("home.medical.medicine_box.field.medicine_type"), value: medicineTypeText(currentBox.medicineType) ?? "")
                MedicineBoxDetailRow(title: L10n.text("medical_record.forms.field.brand_name"), value: currentBox.brandName)
                MedicineBoxDetailRow(title: L10n.text("medical_record.forms.field.dosage_form"), value: currentBox.dosageForm)
                MedicineBoxDetailRow(title: L10n.text("medical_record.forms.field.strength"), value: medicineStrengthDetailValue(currentBox.strength))
            }

            Section(L10n.text("home.medical.medicine_box.section.stock")) {
                MedicineBoxDetailRow(title: L10n.text("home.medical.medicine_box.field.total_quantity"), value: medicineBoxStockText(currentBox))
                if let expireDate = currentBox.expireDate {
                    MedicineBoxDetailRow(
                        title: L10n.text("home.medical.medicine_box.field.expire_date"),
                        value: expireDate.formatted(date: .numeric, time: .omitted)
                    )
                }
            }

            if currentBox.notes.nilIfBlank != nil {
                Section(L10n.text("medical_record.forms.field.notes")) {
                    Text(currentBox.notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            if mode == .server || currentBox.attachments?.isEmpty == false {
                Section {
                    medicineBoxAttachmentsGrid
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    attachmentsSectionHeader
                }
            }
        }
        .navigationTitle(currentBox.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await prepareShareSheet() }
                    } label: {
                        Label(L10n.text("common.share", fallback: "分享"), systemImage: "square.and.arrow.up")
                    }

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
                .disabled(isDeleting || isPreparingShare)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if mode == .localDraft {
                MedicineBoxFormView(
                    mode: .localEdit(
                        existing: MedicineBoxDraft(recognition: currentSourceBoxDraft()),
                        onSubmit: { draft in
                            applyLocalDraftBox(draft.recognitionDraft())
                            showingEditSheet = false
                        }
                    ),
                    entryMemberID: resolvedEntryMemberID,
                    defaultBindingMemberID: currentBox.member,
                    memberOptions: memberOptions,
                    allowsHouseholdPublic: allowsHouseholdPublic,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    typeOptions: typeOptions,
                    specOptionBoxes: specOptionBoxes
                )
            } else {
                MedicineBoxFormView(
                    mode: .serverEdit(existing: currentBox),
                    entryMemberID: resolvedEntryMemberID,
                    defaultBindingMemberID: currentBox.member,
                    memberOptions: memberOptions,
                    allowsHouseholdPublic: allowsHouseholdPublic,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    typeOptions: typeOptions,
                    specOptionBoxes: specOptionBoxes,
                    onServerSaved: { saved in
                        currentBox = saved
                        onSaved(saved)
                        showingEditSheet = false
                    }
                )
            }
        }
        .alert(L10n.text("home.medical.medicine_box.delete.confirm_title"), isPresented: $showingDeleteConfirm) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("common.delete"), role: .destructive) {
                Task { await deleteCurrentBox() }
            }
        } message: {
            Text(L10n.text("home.medical.medicine_box.delete.message"))
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
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
        .onChange(of: box) { newValue in
            currentBox = newValue
        }
    }

    @MainActor
    private func deleteCurrentBox() async {
        guard isDeleting == false else { return }

        if mode == .localDraft {
            onLocalDraftDeleted?()
            dismiss()
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .medicineBoxes, id: currentBox.id)
            onDeleted(currentBox.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func prepareShareSheet() async {
        guard isPreparingShare == false, mode == .server else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let shareAPI = SparkMedicalShareAPI(configuration: workflowAPI.configuration)
            let response = try await shareAPI.createShare(businessType: "medicine_box", businessID: currentBox.id)
            let shareURL = AppEnvironment.current.shareWebBaseURL
                .appendingPathComponent("share")
                .appendingPathComponent(response.shareCode)
            shareContext = MedicalShareContext(
                itemTitle: currentBox.medicineName.nonEmpty ?? L10n.text("home.medical.medicine_box.detail_title"),
                memberName: currentBox.member.flatMap { memberID in
                    memberOptions.first(where: { $0.id == memberID })?.name
                } ?? entryMemberID.flatMap { memberID in
                    memberOptions.first(where: { $0.id == memberID })?.name
                } ?? ownershipDisplay,
                shareURL: shareURL,
                expiresAt: response.expiresAt
            )
        } catch {
            shareErrorMessage = error.localizedDescription.isEmpty ? "生成分享失败" : error.localizedDescription
        }
    }

    private func currentSourceBoxDraft() -> MedicineBoxRecognitionDraft {
        sourceBoxDraft ?? PrescriptionRecognitionDraftMapper.medicineBoxDraft(from: currentBox)
    }

    private func applyLocalDraftBox(_ updated: MedicineBoxRecognitionDraft) {
        sourceBoxDraft = updated
        guard let memberID = entryMemberID ?? currentBox.member else { return }
        currentBox = updated.remoteMedicineBox(memberID: memberID, id: currentBox.id)
        onLocalDraftSaved?(updated)
    }

    private var attachmentsSectionHeader: some View {
        HStack {
            Label(L10n.text("common.attachments"), systemImage: "paperclip")
            Spacer()
            if mode == .server {
                Button(isEditingAttachments
                    ? L10n.text("common.done")
                    : L10n.text("common.manage", fallback: "管理")) {
                    if isEditingAttachments {
                        finishAttachmentEditing()
                    } else {
                        isEditingAttachments = true
                    }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private var medicineBoxAttachmentsGrid: some View {
        MedicalAttachmentGridPreview(
            attachments: currentBox.attachments ?? [],
            fileTransferService: fileTransferService,
            isEditing: mode == .server && isEditingAttachments,
            onDeleted: mode == .server ? { handleAttachmentDeleted(fileID: $0) } : nil,
            onFileUploaded: mode == .server ? { handleFileUploaded($0) } : nil
        )
    }

    private func handleAttachmentDeleted(fileID: Int) {
        var updated = currentBox
        updated.attachments = (updated.attachments ?? []).filter { $0.id != fileID }
        currentBox = updated
        attachmentsDirty = true
    }

    private func finishAttachmentEditing() {
        isEditingAttachments = false
        guard attachmentsDirty else { return }
        attachmentsDirty = false
        onSaved(currentBox)
    }

    private func handleFileUploaded(_ record: ManagedFileRecord) {
        Task {
            do {
                _ = try await fileTransferService.updateBusinessBinding(
                    fileID: record.id,
                    businessType: "medicine_box",
                    businessID: "\(currentBox.id)"
                )
                let newFile = record.remoteManagedFile(
                    businessType: "medicine_box",
                    businessId: "\(currentBox.id)"
                )
                await MainActor.run {
                    var updated = currentBox
                    updated.attachments = (updated.attachments ?? []) + [newFile]
                    currentBox = updated
                    attachmentsDirty = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                }
            }
        }
    }
}
