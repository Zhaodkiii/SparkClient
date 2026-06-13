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

            if let attachments = currentBox.attachments, attachments.isEmpty == false {
                Section(L10n.text("common.attachments")) {
                    MedicalAttachmentGridPreview(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .navigationTitle(currentBox.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.detail_title"))
        .navigationBarTitleDisplayMode(.inline)
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

    private func currentSourceBoxDraft() -> MedicineBoxRecognitionDraft {
        sourceBoxDraft ?? PrescriptionRecognitionDraftMapper.medicineBoxDraft(from: currentBox)
    }

    private func applyLocalDraftBox(_ updated: MedicineBoxRecognitionDraft) {
        sourceBoxDraft = updated
        guard let memberID = entryMemberID ?? currentBox.member else { return }
        currentBox = updated.remoteMedicineBox(memberID: memberID, id: currentBox.id)
        onLocalDraftSaved?(updated)
    }
}
