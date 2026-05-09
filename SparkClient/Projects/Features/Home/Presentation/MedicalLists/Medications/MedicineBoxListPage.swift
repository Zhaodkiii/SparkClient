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
                Text(box.drugName.nilIfBlank ?? box.genericName.nilIfBlank ?? "未命名药品")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(medicineBoxStockText(box))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text([box.strength.nilIfBlank, box.dosageForm.nilIfBlank, medicineTypeText(box.medicineType)].compactMap { $0 }.joined(separator: " · "))
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
        workflowAPI: SparkMedicalWorkflowAPI,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onDeleted: @escaping (Int) -> Void
    ) {
        self.box = box
        self.typeOptions = typeOptions
        self.workflowAPI = workflowAPI
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _currentBox = State(initialValue: box)
    }

    var body: some View {
        List {
            Section("药品信息") {
                MedicineBoxDetailRow(title: "通用名", value: currentBox.genericName)
                MedicineBoxDetailRow(title: "药品名称", value: currentBox.drugName)
                MedicineBoxDetailRow(title: "药品类型", value: medicineTypeText(currentBox.medicineType) ?? "")
                MedicineBoxDetailRow(title: "品牌名", value: currentBox.brandName)
                MedicineBoxDetailRow(title: "剂型", value: currentBox.dosageForm)
                MedicineBoxDetailRow(title: "规格", value: currentBox.strength)
            }

            Section("库存信息") {
                MedicineBoxDetailRow(title: "库存", value: medicineBoxStockText(currentBox))
                if let expireDate = currentBox.expireDate {
                    MedicineBoxDetailRow(title: "有效期", value: expireDate.formatted(date: .numeric, time: .omitted))
                }
                MedicineBoxDetailRow(title: "生产批号", value: currentBox.productionBatch)
            }

            if currentBox.notes.nilIfBlank != nil {
                Section("备注") {
                    Text(currentBox.notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(currentBox.drugName.nilIfBlank ?? currentBox.genericName.nilIfBlank ?? "药品详情")
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
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)?

    @State private var draft: MedicineBoxDraft
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(
        mode: Mode,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        typeOptions: [String] = MedicineBoxTypeCatalog.defaultStoredOptions,
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.typeOptions = MedicineBoxTypeCatalog.mergedOptions(typeOptions)
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
        && draft.genericName.nilIfBlank != nil
        && draft.totalQuantityValue != nil
        && draft.remainingQuantityValue != nil
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
        NavigationView {
            formContent
                .sparkKeyboardDoneToolbar {
                    SparkKeyboardDismiss.endEditing()
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .background(Color(uiColor: .systemGroupedBackground))
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
        .alert("保存失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: "药品信息", titleSystemImage: "pills.fill") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(title: "通用名", text: $draft.genericName, placeholder: "如 对乙酰氨基酚", required: true, keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "药品名称", text: $draft.drugName, placeholder: "如 泰诺林", keyboardVisible: $sheetKeyboardVisible)
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
                        SparkFormTextRow(title: "品牌名", text: $draft.brandName, placeholder: "可选", keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "剂型", text: $draft.dosageForm, placeholder: "片剂 / 胶囊 / 颗粒", keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "规格", text: $draft.strength, placeholder: "如 0.5g*24片", keyboardVisible: $sheetKeyboardVisible)
                    }
                }

                SparkFormCard(title: "库存信息", titleSystemImage: "shippingbox.fill") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(title: "总数量", text: $draft.totalQuantity, placeholder: "如 24", required: true, keyboardVisible: $sheetKeyboardVisible)
                            .keyboardType(.decimalPad)
                        SparkFormTextRow(title: "剩余数量", text: $draft.remainingQuantity, placeholder: "如 24", required: true, keyboardVisible: $sheetKeyboardVisible)
                            .keyboardType(.decimalPad)
                        SparkFormTextRow(title: "单位", text: $draft.unit, placeholder: "片 / 粒 / 袋", keyboardVisible: $sheetKeyboardVisible)
                        Toggle("设置有效期", isOn: $draft.hasExpireDate)
                            .font(.subheadline.weight(.medium))
                        if draft.hasExpireDate {
                            DatePicker("有效期", selection: $draft.expireDate, displayedComponents: .date)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        SparkFormTextRow(title: "生产批号", text: $draft.productionBatch, placeholder: "可选", keyboardVisible: $sheetKeyboardVisible)
                    }
                }

                SparkFormCard(title: "备注", titleSystemImage: "note.text") {
                    SparkFormTextAreaRow(title: "备注", text: $draft.notes, minHeight: 80, maxHeight: 160, placeholder: "用法、存放位置或注意事项", keyboardVisible: $sheetKeyboardVisible)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
            .padding(16)
            .padding(.bottom, 86)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            alertMessage = "请填写通用名、总数量和剩余数量"
            return false
        }
        guard let total = draft.totalQuantityValue, let remaining = draft.remainingQuantityValue else {
            alertMessage = "数量格式不正确"
            return false
        }
        guard remaining <= total else {
            alertMessage = "剩余数量不能大于总数量"
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

struct MedicineBoxDraft {
    var drugName = ""
    var medicineType = MedicineBoxTypeCatalog.defaultStoredValue
    var genericName = ""
    var brandName = ""
    var dosageForm = ""
    var strength = ""
    var totalQuantity = ""
    var remainingQuantity = ""
    var unit = "片"
    var hasExpireDate = false
    var expireDate = Date()
    var productionBatch = ""
    var notes = ""

    init() {}

    init(existing: SparkMedicalSyncAPI.RemoteMedicineBox) {
        drugName = existing.drugName
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: existing.medicineType)
        genericName = existing.genericName
        brandName = existing.brandName
        dosageForm = existing.dosageForm
        strength = existing.strength
        totalQuantity = MedicineBoxDraft.formatQuantity(existing.totalQuantity)
        remainingQuantity = MedicineBoxDraft.formatQuantity(existing.remainingQuantity)
        unit = existing.unit
        if let expireDate = existing.expireDate {
            hasExpireDate = true
            self.expireDate = expireDate
        }
        productionBatch = existing.productionBatch
        notes = existing.notes
    }

    var totalQuantityValue: Double? {
        Double(totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var remainingQuantityValue: Double? {
        Double(remainingQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    fileprivate func payload(memberID: Int) throws -> MedicineBoxPayload {
        guard let totalQuantityValue, let remainingQuantityValue else {
            throw MedicineBoxFormError.invalidQuantity
        }
        return MedicineBoxPayload(
            member: memberID,
            drugName: drugName.nilIfBlank ?? genericName.trimmed,
            medicineType: medicineType.nilIfBlank,
            genericName: genericName.trimmed,
            brandName: brandName.nilIfBlank ?? "",
            dosageForm: dosageForm.nilIfBlank ?? "",
            strength: strength.nilIfBlank ?? "",
            totalQuantity: totalQuantityValue,
            remainingQuantity: remainingQuantityValue,
            unit: unit.nilIfBlank ?? "片",
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            productionBatch: productionBatch.nilIfBlank ?? "",
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
    let drugName: String
    let medicineType: String?
    let genericName: String
    let brandName: String
    let dosageForm: String
    let strength: String
    let totalQuantity: Double
    let remainingQuantity: Double
    let unit: String
    let expireDate: String?
    let productionBatch: String
    let notes: String
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member
        case drugName = "drug_name"
        case medicineType = "medicine_type"
        case genericName = "generic_name"
        case brandName = "brand_name"
        case dosageForm = "dosage_form"
        case strength
        case totalQuantity = "total_quantity"
        case remainingQuantity = "remaining_quantity"
        case unit
        case expireDate = "expire_date"
        case productionBatch = "production_batch"
        case notes
        case extra
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
    "\(box.remainingQuantity.formatted(.number.precision(.fractionLength(0...2))))/\(box.totalQuantity.formatted(.number.precision(.fractionLength(0...2)))) \(box.unit)"
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
