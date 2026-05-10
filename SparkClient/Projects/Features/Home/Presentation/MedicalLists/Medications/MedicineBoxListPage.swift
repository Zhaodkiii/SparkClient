import SwiftUI

struct MedicineBoxListPage: View {
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let memberID: Int?
    let workflowAPI: SparkMedicalWorkflowAPI
    let onMedicineBoxesChanged: ([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void

    @State private var localMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var sheetDestination: MedicineBoxSheetDestination?

    init(
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        memberID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        onMedicineBoxesChanged: @escaping ([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void
    ) {
        self.medicineBoxes = medicineBoxes
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
        _localMedicineBoxes = State(initialValue: medicineBoxes)
    }

    private var sortedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        localMedicineBoxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: localMedicineBoxes)
    }

    var body: some View {
        List {
            if sortedBoxes.isEmpty {
                Text("暂无药箱药品")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedBoxes, id: \.id) { box in
                    NavigationLink {
                        MedicineBoxDetailPage(
                            box: box,
                            typeOptions: medicineTypeOptions,
                            specOptionBoxes: localMedicineBoxes,
                            workflowAPI: workflowAPI,
                            onSaved: upsertMedicineBox,
                            onDeleted: removeMedicineBox
                        )
                    } label: {
                        MedicineBoxRow(box: box)
                    }
                }
            }
        }
        .navigationTitle("药箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .disabled(memberID == nil)
                .accessibilityLabel("添加药品")
            }
        }
        .sheet(item: $sheetDestination) { destination in
            if let memberID {
                MedicineBoxFormView(
                    mode: destination.formMode,
                    memberID: memberID,
                    workflowAPI: workflowAPI,
                    typeOptions: medicineTypeOptions,
                    specOptionBoxes: localMedicineBoxes,
                    onServerSaved: upsertMedicineBox
                )
            } else {
                missingMemberSheet
            }
        }
        .onChange(of: medicineBoxes) { newValue in
            localMedicineBoxes = newValue
        }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = localMedicineBoxes.firstIndex(where: { $0.id == box.id }) {
            localMedicineBoxes[index] = box
        } else {
            localMedicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxesChanged(localMedicineBoxes)
        sheetDestination = nil
    }

    private func removeMedicineBox(id: Int) {
        localMedicineBoxes.removeAll { $0.id == id }
        onMedicineBoxesChanged(localMedicineBoxes)
    }

    @ViewBuilder
    private var missingMemberSheet: some View {
        let content = Text("请先选择成员")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(180)])
        } else {
            content
        }
    }
}

enum MedicineBoxSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicineBox)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let box):
            return "server_\(box.id)"
        }
    }

    var formMode: MedicineBoxFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let box):
            return .serverEdit(existing: box)
        }
    }
}

private struct MedicineBoxRow: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(box.medicineName.nilIfBlank ?? "未命名药品")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(medicineBoxStockText(box))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text([medicineStrengthText(box.strength), box.dosageForm.nilIfBlank, medicineTypeText(box.medicineType)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let expireDate = box.expireDate {
                Text("有效期 \(expireDate.formatted(date: .numeric, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MedicineBoxDetailPage: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let workflowAPI: SparkMedicalWorkflowAPI
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onDeleted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentBox: SparkMedicalSyncAPI.RemoteMedicineBox
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var isDeleting = false

    init(
        box: SparkMedicalSyncAPI.RemoteMedicineBox,
        typeOptions: [String],
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onDeleted: @escaping (Int) -> Void
    ) {
        self.box = box
        self.typeOptions = typeOptions
        self.specOptionBoxes = specOptionBoxes
        self.workflowAPI = workflowAPI
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _currentBox = State(initialValue: box)
    }

    var body: some View {
        List {
            Section("药品信息") {
                MedicineBoxDetailRow(title: "药品名称", value: currentBox.medicineName)
                MedicineBoxDetailRow(title: "药品类型", value: medicineTypeText(currentBox.medicineType) ?? "")
                MedicineBoxDetailRow(title: "品牌名", value: currentBox.brandName)
                MedicineBoxDetailRow(title: "剂型", value: currentBox.dosageForm)
                MedicineBoxDetailRow(title: "规格", value: medicineStrengthDetailValue(currentBox.strength))
            }

            Section("库存信息") {
                MedicineBoxDetailRow(title: "总数量", value: medicineBoxStockText(currentBox))
                if let expireDate = currentBox.expireDate {
                    MedicineBoxDetailRow(title: "有效期", value: expireDate.formatted(date: .numeric, time: .omitted))
                }
            }

            if currentBox.notes.nilIfBlank != nil {
                Section("备注") {
                    Text(currentBox.notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(currentBox.medicineName.nilIfBlank ?? "药品详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            MedicineBoxFormView(
                mode: .serverEdit(existing: currentBox),
                memberID: currentBox.member,
                workflowAPI: workflowAPI,
                typeOptions: typeOptions,
                specOptionBoxes: specOptionBoxes,
                onServerSaved: { saved in
                    currentBox = saved
                    onSaved(saved)
                    showingEditSheet = false
                }
            )
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentBox() }
            }
        } message: {
            Text("删除后该药品将从药箱中移除。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
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
}

struct MedicineBoxFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteMedicineBox)
        case localEdit(existing: MedicineBoxDraft, onSubmit: (MedicineBoxDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)?

    @State private var draft: MedicineBoxDraft
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showDosageFormSheet = false
    @State private var showSpecificationSheet = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    /// Chrome outside the measured scroll content (inline nav + `sparkFormBottomBar`), aligned with `MedicineBoxSpecificationSheet` detent math.
    private static let formSheetNavChromeHeight: CGFloat = 72
    private static let formSheetBottomBarChromeHeight: CGFloat = 88

    init(
        mode: Mode,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        typeOptions: [String] = MedicineBoxTypeCatalog.defaultStoredOptions,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.typeOptions = MedicineBoxTypeCatalog.mergedOptions(typeOptions)
        self.specOptionBoxes = specOptionBoxes
        self.onServerSaved = onServerSaved

        switch mode {
        case .create:
            _draft = State(initialValue: MedicineBoxDraft())
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicineBoxDraft(existing: existing))
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
        }
    }

    private var canSubmit: Bool {
        isSubmitting == false
        && draft.medicineName.nilIfBlank != nil
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "添加药品"
        case .serverEdit, .localEdit:
            return "编辑药品"
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


        .alert("保存失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
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
                SparkFormCard(title: "药品信息", titleSystemImage: "pills.fill") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(title: "药品名称", text: $draft.medicineName, placeholder: "如 对乙酰氨基酚或泰诺林", required: true, keyboardVisible: $sheetKeyboardVisible)
                        
                        VStack{
                            Toggle("设置有效期", isOn: $draft.hasExpireDate)
                                .font(.subheadline.weight(.medium))
                            if draft.hasExpireDate {
                                DatePicker("有效期", selection: $draft.expireDate, displayedComponents: .date)
                                    .font(.subheadline.weight(.medium))
//                                    .padding(.horizontal, 12)
//                                    .frame(height: 44)
                                    .sparkFormTextFieldChrome(isFocused: false, isError: false)

//                                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        
                        SparkFormMenuCustomRow(
                            title: "药品类型",
                            required: false,
                            sections: [(nil, MedicineBoxTypeCatalog.displayOptions(for: typeOptions))],
                            text: medicineTypeBinding,
                            customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                            customPlaceholder: "输入药品类型",
                            keyboardVisible: $sheetKeyboardVisible,
                            optionSystemImage: MedicineBoxTypeCatalog.systemImage(for:),
                            customAutofocus: false
                        )
                        MedicineBoxStrengthPickerRow(
                            title: L10n.text("medical_record.forms.field.dosage_form", fallback: "剂型"),
                            displayValue: MedicineBoxDosageFormCatalog.displayString(stored: draft.dosageForm),
                            placeholder: L10n.text("medical_record.medicine_box.dosage_form_sheet.placeholder", fallback: "请选择剂型")
                        ) {
                            showDosageFormSheet.toggle()
                        }

                        MedicineBoxStrengthPickerRow(
                            title: L10n.text("medical_record.forms.field.strength"),
                            displayValue: draft.specification.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                            placeholder: L10n.text("medical_record.medicine_box.strength_sheet.placeholder")
                        ){
                            showSpecificationSheet.toggle()
                        }
                        
                        SparkFormTextRow(title: "总数量", text: $draft.totalQuantity, placeholder: "如 24", keyboardVisible: $sheetKeyboardVisible)
                            .keyboardType(.decimalPad)
                    }
                }
                
                SparkFormCard(title: "更多信息", titleSystemImage: "shippingbox.fill") {
                    
                    SparkFormTextRow(title: "品牌名", text: $draft.brandName, placeholder: "可选", keyboardVisible: $sheetKeyboardVisible)
                    
                    SparkFormTextAreaRow(title: "备注", text: $draft.notes, minHeight: 80, maxHeight: 160, placeholder: "用法、存放位置或注意事项", keyboardVisible: $sheetKeyboardVisible)
                }

            }
        }
    }

    private var medicineTypeBinding: Binding<String> {
        Binding(
            get: { MedicineBoxTypeCatalog.displayString(stored: draft.medicineType) },
            set: { draft.medicineType = MedicineBoxTypeCatalog.storedValue(fromDisplay: $0) }
        )
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
            let payload = try draft.payload(memberID: memberID)
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
            alertMessage = "请填写药品名称"
            return false
        }
        return true
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

// MARK: - Specification sheet (structured fields; same row + sheet chrome as legacy strength picker)

private struct MedicineBoxStrengthPickerRow: View {
    let title: String
    let displayValue: String
    let placeholder: String
//    @Binding var isPresented: Bool
    var onTap: (() -> Void)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Button {
                onTap()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(resolvedLabel)
                        .font(.body)
                        .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .sparkFormTextFieldChrome(isFocused: false, isError: false)
//                .padding(.horizontal, 12)
//                .frame(minHeight: 44)
//                .background(Color(uiColor: .systemBackground))
//                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .stroke(Color(uiColor: .separator), lineWidth: 1)
//                )
            }
            .buttonStyle(.plain)
        }

    }

    private var trimmedDisplay: String {
        displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPlaceholder: Bool {
        trimmedDisplay.isEmpty
    }

    private var resolvedLabel: String {
        isPlaceholder ? placeholder : displayValue
    }
}

private struct MedicineBoxDosageFormPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    MedicineBoxDosageFormHeaderIcon()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                    Text(L10n.text("medical_record.medicine_box.dosage_form_sheet.title", fallback: "选取药品类型"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)

                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.common_section", fallback: "常见形式"),
                        items: MedicineBoxDosageFormCatalog.commonForms
                    )
                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.more_section", fallback: "更多形式"),
                        items: MedicineBoxDosageFormCatalog.moreForms
                    )
                }
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.text("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func dosageFormSection(title: String, items: [MedicineBoxDosageFormCatalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Section(L10n.text(title)) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.storedValue) { index, item in
                        Button {
                            select(item)
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.displayName)
                                    .font(.title3)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if normalizedSelection == item.storedValue {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .font(.title3.bold())
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: normalizedSelection)
    }

    private func select(_ item: MedicineBoxDosageFormCatalog.Item) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = item.storedValue
        }
        dismiss()
    }

    private var normalizedSelection: String {
        selection.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MedicineBoxDosageFormCatalog {
    struct Item: Hashable {
        let storedValue: String
        let localizationKey: String
        let fallback: String

        var displayName: String {
            L10n.text(localizationKey, fallback: fallback)
        }
    }

    static let commonForms: [Item] = [
        item("胶囊", key: "capsule", fallback: "胶囊"),
        item("药片", key: "tablet", fallback: "药片"),
        item("液体", key: "liquid", fallback: "液体"),
        item("外用", key: "topical", fallback: "外用")
    ]

    static let moreForms: [Item] = [
        item("乳液", key: "lotion", fallback: "乳液"),
        item("乳霜", key: "cream", fallback: "乳霜"),
        item("凝胶", key: "gel", fallback: "凝胶"),
        item("吸入剂", key: "inhaler", fallback: "吸入剂"),
        item("喷剂", key: "spray", fallback: "喷剂"),
        item("栓剂", key: "suppository", fallback: "栓剂"),
        item("泡沫", key: "foam", fallback: "泡沫"),
        item("注射", key: "injection", fallback: "注射"),
        item("滴剂", key: "drops", fallback: "滴剂"),
        item("粉末", key: "powder", fallback: "粉末"),
        item("设备", key: "device", fallback: "设备"),
        item("贴剂", key: "patch", fallback: "贴剂"),
        item("软膏", key: "ointment", fallback: "软膏")
    ]

    static func displayString(stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return allForms.first { $0.storedValue == trimmed }?.displayName ?? trimmed
    }

    private static var allForms: [Item] {
        commonForms + moreForms
    }

    private static func item(_ storedValue: String, key: String, fallback: String) -> Item {
        Item(
            storedValue: storedValue,
            localizationKey: "medical_record.medicine_box.dosage_form.\(key)",
            fallback: fallback
        )
    }
}

private struct MedicineBoxDosageFormHeaderIcon: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "pills.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.multicolor)

            Image(systemName: "cross.case.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemTeal))

            Image(systemName: "drop.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))

            Image(systemName: "bandage.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemPink))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MedicineBoxSpecificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var specification: MedicineSpecification
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempSpec: MedicineSpecification
    @FocusState private var doseValueFocused: Bool
    @FocusState private var packageCountFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    init(
        specification: Binding<MedicineSpecification>,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    ) {
        _specification = specification
        self.specOptionBoxes = specOptionBoxes
        _tempSpec = State(initialValue: specification.wrappedValue)
    }

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var innerUnitLabels: [String] {
        MedicineSpecificationCatalog.innerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var outerUnitLabels: [String] {
        MedicineSpecificationCatalog.outerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var previewLine: String {
        let t = tempSpec.displayString(prefersEnglish: prefersEnglish)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L10n.text("medical_record.medicine_box.spec.preview_empty") : t
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    legacyFreeformBlock
                    
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.dose_value")) {
                        TextField("5", text: doseValueBinding)
                            .textFieldStyle(.plain)
                            .focused($doseValueFocused)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.dose_unit"),
                        labels: doseUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempSpec.doseUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                        }
                    )
                    
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.package_count")) {
                        TextField("28", text: packageCountBinding)
                            .textFieldStyle(.plain)
                            .focused($packageCountFocused)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.package_unit"),
                        labels: innerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedInnerPackage(fromAny: tempSpec.packageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.packageUnit = MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                        }
                    )
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.outer_unit"),
                        labels: outerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedOuterPackage(fromAny: tempSpec.outerPackageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.outerPackageUnit = MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                        }
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("medical_record.medicine_box.spec.preview"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text(previewLine)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medical_record.medicine_box.strength_sheet.title"))
            .sparkKeyboardDoneToolbar {
                SparkKeyboardDismiss.endEditing()
            }
            .sparkFormBottomBar(
                canSubmit: true,
                cancelTitle: L10n.text("common.cancel"),
                saveTitle: L10n.text("common.done"),
                saveSystemImage: "checkmark.circle.fill",
                onCancel: {
                    dismiss()
                },
                onSave: {
                    specification = tempSpec
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            tempSpec = specification
        }
    }

    @ViewBuilder
    private var legacyFreeformBlock: some View {
        if tempSpec.rawLegacyStrength != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("medical_record.medicine_box.strength_sheet.custom_section"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                TextField(
                    L10n.text("medical_record.medicine_box.strength_sheet.placeholder"),
                    text: Binding(
                        get: { tempSpec.rawLegacyStrength ?? "" },
                        set: { newValue in
                            let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            tempSpec.rawLegacyStrength = t.isEmpty ? nil : t
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(uiColor: .separator).opacity(0.35))
            }
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempSpec.doseValue },
            set: {
                tempSpec.doseValue = $0
                tempSpec.rawLegacyStrength = nil
            }
        )
    }

    private var packageCountBinding: Binding<String> {
        Binding(
            get: { tempSpec.packageCount },
            set: {
                tempSpec.packageCount = $0
                tempSpec.rawLegacyStrength = nil
            }
        )
    }

    private func sheetFieldBlock(title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }

    private func unitChipBlock(
        title: String,
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(labels, id: \.self) { label in
                    let selected = isSelected(label)
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.system(size: 14))
                            .foregroundColor(selected ? .white : Color.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(selected ? Self.selectedChip : Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }
}

struct MedicineBoxDraft {
    var medicineName = ""
    var medicineType = MedicineBoxTypeCatalog.defaultStoredValue
    var brandName = ""
    var dosageForm = ""
    /// Structured specification; encoded to API `strength` via ``MedicineSpecification/storedStrengthString``.
    var specification = MedicineSpecification()
    var totalQuantity = ""
    var hasExpireDate = false
    var expireDate = Date()
    var notes = ""

    init() {}

    init(existing: SparkMedicalSyncAPI.RemoteMedicineBox) {
        medicineName = existing.medicineName
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: existing.medicineType)
        brandName = existing.brandName
        dosageForm = existing.dosageForm
        let parsed = MedicineSpecification.parse(fromAPIStrength: existing.strength)
        if parsed.hasStructuredContent {
            specification = parsed
        } else if existing.strength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            specification = MedicineSpecification(rawLegacyOnly: existing.strength)
        } else {
            specification = MedicineSpecification()
        }
        if let q = existing.totalQuantity {
            totalQuantity = MedicineBoxDraft.formatQuantity(q)
        } else {
            totalQuantity = ""
        }
        if let expireDate = existing.expireDate {
            hasExpireDate = true
            self.expireDate = expireDate
        }
        notes = existing.notes
    }

    var totalQuantityValue: Double? {
        Double(totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    fileprivate func payload(memberID: Int) throws -> MedicineBoxPayload {
        let trimmedQty = totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTotal: Double?
        if trimmedQty.isEmpty {
            resolvedTotal = nil
        } else if let v = Double(trimmedQty) {
            resolvedTotal = v
        } else {
            throw MedicineBoxFormError.invalidQuantity
        }
        return MedicineBoxPayload(
            member: memberID,
            medicineName: medicineName.trimmed,
            medicineType: medicineType.nilIfBlank,
            brandName: brandName.nilIfBlank ?? "",
            dosageForm: dosageForm.nilIfBlank ?? "",
            strength: specification.storedStrengthString.nilIfBlank ?? "",
            totalQuantity: resolvedTotal,
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            notes: notes.nilIfBlank ?? "",
            extra: [:]
        )
    }

    private static func formatQuantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct MedicineBoxPayload: Encodable {
    let member: Int
    let medicineName: String
    let medicineType: String?
    let brandName: String
    let dosageForm: String
    let strength: String
    let totalQuantity: Double?
    let expireDate: String?
    let notes: String
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member
        case medicineName = "medicine_name"
        case medicineType = "medicine_type"
        case brandName = "brand_name"
        case dosageForm = "dosage_form"
        case strength
        case totalQuantity = "total_quantity"
        case expireDate = "expire_date"
        case notes
        case extra
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(member, forKey: .member)
        try c.encode(medicineName, forKey: .medicineName)
        try c.encodeIfPresent(medicineType, forKey: .medicineType)
        try c.encode(brandName, forKey: .brandName)
        try c.encode(dosageForm, forKey: .dosageForm)
        try c.encode(strength, forKey: .strength)
        try c.encodeIfPresent(totalQuantity, forKey: .totalQuantity)
        try c.encodeIfPresent(expireDate, forKey: .expireDate)
        try c.encode(notes, forKey: .notes)
        try c.encode(extra, forKey: .extra)
    }
}

private enum MedicineBoxFormError: LocalizedError {
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .invalidQuantity:
            return "数量格式不正确"
        }
    }
}

private struct MedicineBoxDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "未填写" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

enum MedicineBoxTypeCatalog {
    nonisolated static let defaultStoredValue = ""

    nonisolated static let defaults: [SparkBilingualItem] = [
        .init(cn: "感冒发烧", en: "Cold & Fever"),
        .init(cn: "胃肠消化", en: "GI & Digestion"),
        .init(cn: "咳嗽咽痛", en: "Cough & Throat"),
        .init(cn: "皮肤骨痛", en: "Skin, Bone & Pain"),
        .init(cn: "慢病用药", en: "Chronic Medication"),
        .init(cn: "儿童用药", en: "Pediatric")
    ]

    nonisolated static let defaultStoredOptions: [String] = defaults.map(\.cn)

    nonisolated private static let legacyCodeMap: [String: String] = [
        "cold_fever": "感冒发烧",
        "gi_digestion": "胃肠消化",
        "cough_throat": "咳嗽咽痛",
        "skin_bone": "皮肤骨痛",
        "chronic": "慢病用药",
        "pediatric": "儿童用药",
        "uncategorized": ""
    ]

    nonisolated private static var prefersEnglish: Bool {
        if #available(iOS 16, *) {
            let code = Locale.current.language.languageCode?.identifier ?? ""
            return code.hasPrefix("zh") == false
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == false
    }

    nonisolated static func options(in boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let custom = boxes.compactMap { blankToNil(storedValue(fromAny: $0.medicineType)) }
        return mergedOptions(defaultStoredOptions + custom)
    }

    nonisolated static func mergedOptions(_ values: [String]) -> [String] {
        uniqued(values.map(storedValue(fromAny:)))
    }

    nonisolated static func displayOptions(for values: [String]) -> [String] {
        uniqued(values).map(displayString(stored:))
    }

    nonisolated static func displayString(stored: String?) -> String {
        let stored = storedValue(fromAny: stored)
        guard let item = defaults.first(where: { $0.cn == stored || $0.en == stored }) else {
            return blankToNil(stored) ?? defaultStoredValue
        }
        return prefersEnglish ? item.en : item.cn
    }

    nonisolated static func storedValue(fromDisplay display: String) -> String {
        let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = defaults.first(where: { $0.cn == text || $0.en == text }) {
            return item.cn
        }
        return text
    }

    nonisolated static func storedValue(fromAny raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return defaultStoredValue
        }
        if let mapped = legacyCodeMap[raw] {
            return mapped
        }
        if let item = defaults.first(where: { $0.cn == raw || $0.en == raw }) {
            return item.cn
        }
        return raw
    }

    nonisolated static func systemImage(for display: String) -> String? {
        switch storedValue(fromDisplay: display) {
        case "感冒发烧":
            return "thermometer.medium"
        case "胃肠消化":
            return "cross.case"
        case "咳嗽咽痛":
            return "lungs"
        case "皮肤骨痛":
            return "figure.walk"
        case "慢病用药":
            return "calendar.badge.clock"
        case "儿童用药":
            return "person.crop.circle"
        default:
            return "tag"
        }
    }

    nonisolated private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = storedValue(fromAny: trimmed)
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    nonisolated private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func medicineBoxStockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return "未填写" }
    return q.formatted(.number.precision(.fractionLength(0...2)))
}

private func medicineStrengthText(_ strength: String?) -> String? {
    guard let raw = strength?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else { return nil }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

private func medicineStrengthDetailValue(_ strength: String) -> String {
    let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.isEmpty == false else { return "" }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

private func medicineTypeText(_ type: String?) -> String? {
    guard let type, !type.isEmpty else { return nil }
    return MedicineBoxTypeCatalog.displayString(stored: type)
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
