import SwiftUI

struct MedicineBoxFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteMedicineBox)
        case localEdit(existing: MedicineBoxDraft, onSubmit: (MedicineBoxDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let entryMemberID: Int
    let allowsHouseholdPublic: Bool
    let memberOptions: [Member]
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService?
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)?

    @State private var draft: MedicineBoxDraft
    @State private var bindingMemberID: Int?
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showDosageFormSheet = false
    @State private var showSpecificationSheet = false
    @State private var pendingAttachmentFiles: [MedicalUploadLocalFile] = []
    @State private var localAttachmentPreview: FilePreviewInput?
    @State private var localAttachmentPreviewIndex: Int = 0

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    /// Chrome outside the measured scroll content (inline nav + `sparkFormBottomBar`), aligned with `MedicineBoxSpecificationSheet` detent math.
    private static let formSheetNavChromeHeight: CGFloat = 72
    private static let formSheetBottomBarChromeHeight: CGFloat = 88

    init(
        mode: Mode,
        entryMemberID: Int,
        defaultBindingMemberID: Int? = nil,
        memberOptions: [Member] = [],
        allowsHouseholdPublic: Bool = false,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService? = nil,
        typeOptions: [String] = MedicineBoxTypeCatalog.defaultStoredOptions,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)? = nil
    ) {
        self.mode = mode
        self.entryMemberID = entryMemberID
        self.memberOptions = memberOptions
        self.allowsHouseholdPublic = allowsHouseholdPublic
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.typeOptions = MedicineBoxTypeCatalog.mergedOptions(typeOptions)
        self.specOptionBoxes = specOptionBoxes
        self.onServerSaved = onServerSaved

        let initialBinding: Int?
        switch mode {
        case .create:
            _draft = State(initialValue: MedicineBoxDraft())
            initialBinding = allowsHouseholdPublic
                ? defaultBindingMemberID
                : (defaultBindingMemberID ?? entryMemberID)
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicineBoxDraft(existing: existing))
            initialBinding = existing.member ?? defaultBindingMemberID
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
            initialBinding = allowsHouseholdPublic
                ? defaultBindingMemberID
                : (defaultBindingMemberID ?? entryMemberID)
        }
        _bindingMemberID = State(initialValue: allowsHouseholdPublic ? initialBinding : (initialBinding ?? entryMemberID))
    }

    private var canSubmit: Bool {
        isSubmitting == false
        && draft.medicineName.nilIfBlank != nil
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return L10n.text("home.medical.medicine_box.form.add_title")
        case .serverEdit, .localEdit:
            return L10n.text("home.medical.medicine_box.form.edit_title")
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            formContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("MedicineBoxFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                        dismiss()
                    },
                    onSave: {
                        guard canSubmit else { return }
                        submitDraft()
                    }
                )
        }
        .interactiveDismissDisabled(isSubmitting)
//        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
        .background(Color(uiColor: .systemBackground))
        .unifiedFilePreview(
            isPresented: Binding(
                get: { localAttachmentPreview != nil },
                set: { isPresented in
                    if isPresented == false {
                        localAttachmentPreview = nil
                    }
                }
            ),
            files: pendingAttachmentFiles,
            startIndex: localAttachmentPreviewIndex
        )


        .alert(L10n.text("home.medical.medicine_box.save_failed"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showSpecificationSheet) {
            MedicineBoxSpecificationSheet(
                specification: $draft.specification,
                specOptionBoxes: specOptionBoxes
            )

        }
        .sheet(isPresented: $showDosageFormSheet) {
            MedicineBoxDosageFormPickerSheet(selection: $draft.dosageForm)
        }
    }

    private var formContent: some View {
        AdaptiveToolSheetScrollView(
            bottomContentPadding: 24,
            extraChromeHeight: Self.formSheetNavChromeHeight + Self.formSheetBottomBarChromeHeight
        ) {
            VStack(spacing: 14) {

                if allowsHouseholdPublic {
                    SparkFormCard(title: L10n.text("home.medical.medicine_box.section.ownership"), titleSystemImage: "person.2.fill") {
                        ownershipPicker
                    }
                }

                SparkFormCard(title: L10n.text("home.medical.medicine_box.section.info"), titleSystemImage: "pills.fill") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(
                            title: L10n.text("home.medical.medicine_box.field.medicine_name"),
                            text: $draft.medicineName,
                            placeholder: L10n.text("home.medical.medicine_box.form.name_placeholder"),
                            required: true,
                            keyboardVisible: $sheetKeyboardVisible
                        )
                        
                        VStack{
                            Toggle(L10n.text("home.medical.medicine_box.field.set_expire"), isOn: $draft.hasExpireDate)
                                .font(.subheadline.weight(.medium))
                            if draft.hasExpireDate {
                                DatePicker(
                                    L10n.text("home.medical.medicine_box.field.expire_date"),
                                    selection: $draft.expireDate,
                                    displayedComponents: .date
                                )
                                    .font(.subheadline.weight(.medium))
//                                    .padding(.horizontal, 12)
//                                    .frame(height: 44)
                                    .sparkFormTextFieldChrome(isFocused: false, isError: false)
//                                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        
                        SparkFormMenuCustomRow(
                            title: L10n.text("home.medical.medicine_box.field.medicine_type"),
                            required: false,
                            sections: [(nil, MedicineBoxTypeCatalog.displayOptions(for: typeOptions))],
                            text: medicineTypeBinding,
                            customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                            customPlaceholder: L10n.text("home.medical.medicine_box.form.type_placeholder"),
                            keyboardVisible: $sheetKeyboardVisible,
                            optionSystemImage: MedicineBoxTypeCatalog.systemImage(for:),
                            customAutofocus: false
                        )
                        SparkFormSheetPickerRow(
                            title: L10n.text("medical_record.forms.field.dosage_form"),
                            displayValue: MedicineBoxDosageFormCatalog.displayString(stored: draft.dosageForm),
                            placeholder: L10n.text("medical_record.medicine_box.dosage_form_sheet.placeholder")
                        ) {
                            showDosageFormSheet.toggle()
                        }

                        SparkFormSheetPickerRow(
                            title: L10n.text("medical_record.forms.field.strength"),
                            displayValue: draft.specification.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                            placeholder: L10n.text("medical_record.medicine_box.strength_sheet.placeholder")
                        ) {
                            showSpecificationSheet.toggle()
                        }
                        
                        SparkFormTextRow(
                            title: L10n.text("home.medical.medicine_box.field.total_quantity"),
                            text: $draft.totalQuantity,
                            placeholder: L10n.text("home.medical.medicine_box.form.qty_placeholder"),
                            keyboardVisible: $sheetKeyboardVisible
                        )
                            .keyboardType(.decimalPad)
                    }
                }
                
                SparkFormCard(title: L10n.text("home.medical.medicine_box.form.more_info"), titleSystemImage: "shippingbox.fill") {
                    
                    SparkFormTextRow(
                        title: L10n.text("medical_record.forms.field.brand_name"),
                        text: $draft.brandName,
                        placeholder: L10n.text("home.medical.medicine_box.form.brand_placeholder"),
                        keyboardVisible: $sheetKeyboardVisible
                    )
                    
                    SparkFormTextAreaRow(
                        title: L10n.text("medical_record.forms.field.notes"),
                        text: $draft.notes,
                        minHeight: 80,
                        maxHeight: 160,
                        placeholder: L10n.text("home.medical.medicine_box.form.notes_placeholder"),
                        keyboardVisible: $sheetKeyboardVisible
                    )
                }

                if fileTransferService != nil {
                    attachmentFormCard
                }

            }
        }
    }

    private var attachmentFormCard: some View {
        SparkFormCard(title: L10n.text("common.attachments"), titleSystemImage: "paperclip") {
            VStack(alignment: .leading, spacing: 12) {
                if let fileTransferService, draft.attachments.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("home.medical.medicine_box.attachment.saved"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        MedicalAttachmentListView(
                            attachments: draft.attachments,
                            fileTransferService: fileTransferService
                        )
                    }
                }

                if pendingAttachmentFiles.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("home.medical.medicine_box.attachment.pending"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 12
                        ) {
                            ForEach(pendingAttachmentFiles) { file in
                                MedicalDocumentFilePreviewSquareCard(
                                    item: file.previewInput,
                                    onPreview: {
                                        localAttachmentPreview = file.previewInput
                                        if let index = pendingAttachmentFiles.firstIndex(where: { $0.id == file.id }) {
                                            localAttachmentPreviewIndex = index
                                        }
                                    },
                                    onDelete: { pendingAttachmentFiles.removeAll { $0.id == file.id } }
                                )
                            }
                        }
                    }
                }

                attachmentPickerButton
            }
        }
    }

    @ViewBuilder
    private var attachmentPickerButton: some View {
        MedicalDocumentFilePickerMenu(
            buttonContent: { addAttachmentButtonLabel },
            onFilesSelected: appendAttachmentFiles
        )
    }

    private var addAttachmentButtonLabel: some View {
        Label(L10n.text("home.medical.medicine_box.attachment.add"), systemImage: "plus.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
    }

    private func appendAttachmentFiles(_ files: [MedicalUploadLocalFile]) {
        pendingAttachmentFiles.append(contentsOf: files)
    }

    private var medicineTypeBinding: Binding<String> {
        Binding(
            get: { MedicineBoxTypeCatalog.displayString(stored: draft.medicineType) },
            set: { draft.medicineType = MedicineBoxTypeCatalog.storedValue(fromDisplay: $0) }
        )
    }

    private var ownershipPicker: some View {
        Menu {
            Button {
                bindingMemberID = nil
            } label: {
                if bindingMemberID == nil {
                    Label(L10n.text("home.medical.medicine_box.ownership.household"), systemImage: "checkmark")
                } else {
                    Text(L10n.text("home.medical.medicine_box.ownership.household"))
                }
            }
            if memberOptions.isEmpty {
                Button {
                    bindingMemberID = entryMemberID
                } label: {
                    if bindingMemberID == entryMemberID {
                        Label(L10n.text("home.medical.medicine_box.ownership.current_member"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("home.medical.medicine_box.ownership.current_member"))
                    }
                }
            } else {
                ForEach(memberOptions) { member in
                    Button {
                        bindingMemberID = member.id
                    } label: {
                        if bindingMemberID == member.id {
                            Label(member.name, systemImage: "checkmark")
                        } else {
                            Text(member.name)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(L10n.text("home.medical.medicine_box.section.ownership"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(ownershipPickerTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .sparkFormTextFieldChrome(isFocused: false, isError: false)
        }
    }

    private var ownershipPickerTitle: String {
        if bindingMemberID == nil {
            return L10n.text("home.medical.medicine_box.ownership.household")
        }
        if let id = bindingMemberID,
           let member = memberOptions.first(where: { $0.id == id }) {
            return member.name
        }
        return L10n.text("home.medical.medicine_box.ownership.member_fallback")
    }

    private func submitDraft() {
        switch mode {
        case .localEdit(_, let onSubmit):
            guard validateDraft() else { return }
            onSubmit(draft)
            dismiss()
        case .create, .serverEdit:
            Task { await submitToServer() }
        }
    }

    @MainActor
    private func submitToServer() async {
        guard validateDraft() else { return }
        guard isSubmitting == false else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let uploadedFileIDs = try await uploadPendingAttachmentsIfNeeded()
            let fileIDs = draft.attachments.map(\.id) + uploadedFileIDs
            let payload = try draft.payload(
                entryMemberID: entryMemberID,
                bindingMemberID: allowsHouseholdPublic ? bindingMemberID : entryMemberID,
                fileIds: fileIDs
            )
            let saved: SparkMedicalSyncAPI.RemoteMedicineBox
            switch mode {
            case .create:
                saved = try await workflowAPI.create(
                    SparkMedicalSyncAPI.RemoteMedicineBox.self,
                    kind: .medicineBoxes,
                    body: payload
                )
            case .serverEdit(let existing):
                saved = try await workflowAPI.update(
                    SparkMedicalSyncAPI.RemoteMedicineBox.self,
                    kind: .medicineBoxes,
                    id: existing.id,
                    body: payload
                )
            case .localEdit:
                return
            }
            onServerSaved?(saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func validateDraft() -> Bool {
        guard canSubmit else {
            alertMessage = L10n.text("home.medical.medicine_box.form.validation_name")
            return false
        }
        return true
    }

    private func uploadPendingAttachmentsIfNeeded() async throws -> [Int] {
        guard pendingAttachmentFiles.isEmpty == false else { return [] }
        guard let fileTransferService else { return [] }

        let uploader = UploadMedicalDocumentFilesUseCase(fileTransferService: fileTransferService)
        let uploaded = try await uploader.execute(memberID: bindingMemberID ?? entryMemberID, files: pendingAttachmentFiles)
        return uploaded.compactMap { $0.remoteFile?.id }
    }

    private var modeLogLabel: String {
        switch mode {
        case .create:
            return "create"
        case .serverEdit:
            return "serverEdit"
        case .localEdit:
            return "localEdit"
        }
    }
}
