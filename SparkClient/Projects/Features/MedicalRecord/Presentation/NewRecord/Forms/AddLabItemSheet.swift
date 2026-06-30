import SwiftUI

private let sparkLabCommonUnits: [String] = [
    "g/L", "10^9/L", "10^12/L", "%", "fL", "pg", "U/L", "IU/L"
]

private let sparkLabMoreUnits: [String] = [
    "mmol/L", "μmol/L", "mg/L", "ng/mL", "pmol/L", "mIU/L", "IU/mL",
    "mmHg", "次/分", "℃", "μg/L", "nmol/L"
]

// MARK: - 结果状态（对齐 Health `ResultStatusPickerRow`：菜单 + SF Symbol）

private enum SparkLabResultFlag: String, CaseIterable, Identifiable {
    case normal
    case high
    case low
    case abnormal
    case up
    case down
    case h
    case l

    var id: String { rawValue }

    /// 写入 `MedicalReportItem.flag` 的展示字符串（与既有 L10n 选项一致）。
    var storageString: String {
        switch self {
        case .normal: return L10n.text("medical_record.forms.lab_item.flag.normal")
        case .high: return L10n.text("medical_record.forms.lab_item.flag.high")
        case .low: return L10n.text("medical_record.forms.lab_item.flag.low")
        case .abnormal: return L10n.text("medical_record.forms.lab_item.flag.abnormal")
        case .up: return "↑"
        case .down: return "↓"
        case .h: return "H"
        case .l: return "L"
        }
    }

    var title: String { storageString }

    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle"
        case .high: return "arrow.up.circle"
        case .low: return "arrow.down.circle"
        case .abnormal: return "exclamationmark.triangle"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .h: return "h.circle"
        case .l: return "l.circle"
        }
    }

    static func fromStoredFlag(_ flag: String) -> SparkLabResultFlag {
        let t = flag.trimmingCharacters(in: .whitespacesAndNewlines)
        for c in Self.allCases where c.storageString == t { return c }
        switch t {
        case "↑": return .up
        case "↓": return .down
        case "H", "h": return .h
        case "L", "l": return .l
        default:
            return .normal
        }
    }

    /// `fromStoredFlag` 对无法识别的值会回落到 `.normal`；用「是否与本地化后的正常文案一致」区分预置正常与自定义自由文本。
    static func isPredefinedStoredValue(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return false }
        let resolved = fromStoredFlag(t)
        let normalLabel = Self.normal.storageString
        if resolved == .normal, t != normalLabel { return false }
        return true
    }
}

/// 检验报告子项：布局参考 Health `AddLabItemSheet`；底部使用 `sparkFormBottomBar`（取消 / 完成）。
struct AddLabItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ItemDraft
    let onSubmit: (ItemDraft) -> Void

    @State private var sheetKeyboardVisible = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(draft: ItemDraft, onSubmit: @escaping (ItemDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSubmit = onSubmit
    }

    private var canSubmit: Bool {
        let t: (String?) -> Bool = { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        return t(draft.itemName)
            && t(draft.resultValue)
            && t(draft.unit)
            && t(draft.flag)
    }

    var body: some View {
        CompatibleNavigationContainer {
            formScroll
                .navigationTitle(L10n.text("medical_record.forms.lab_item.nav_title"))
                .navigationBarTitleDisplayMode(.inline)
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("AddLabItemSheet: cancel tapped", module: formLogModule)
                        dismiss()
                    },
                    onSave: {
                        guard canSubmit else { return }
                        submitDraft()
                        dismiss()
                    }
                )
        }
        .sparkKeyboardDoneToolbar {
            SparkKeyboardDismiss.endEditing()
        }
    }

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("medical_record.forms.lab_item.nav_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                HStack(alignment: .top, spacing: 12) {
                    SparkFormTextRow(
                        title: L10n.text("medical_record.forms.field.item_name"),
                        text: $draft.optionalField(\.itemName),
                        placeholder: L10n.text("medical_record.forms.lab_item.placeholder.item_name"),
                        required: true,
                        keyboardVisible: $sheetKeyboardVisible
                    )
                    SparkFormTextRow(
                        title: L10n.text("common.result"),
                        text: $draft.optionalField(\.resultValue),
                        placeholder: L10n.text("medical_record.forms.lab_item.placeholder.result"),
                        required: true,
                        keyboardVisible: $sheetKeyboardVisible
                    )
                }

                labUnitRow

                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.field.reference_range"),
                    text: $draft.optionalField(\.referenceRange),
                    placeholder: L10n.text("medical_record.forms.lab_item.placeholder.reference"),
                    keyboardVisible: $sheetKeyboardVisible
                )

                labFlagRow

                VisitDivider(color: Color(.separator), height: 1, verticalPadding: 8)

                Text(L10n.text("medical_record.forms.lab_item.section_category_override"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SparkLabExamCategoryCascadeRow(
                    primaryTitle: L10n.text("medical_record.forms.field.category"),
                    secondaryTitle: L10n.text("medical_record.forms.field.subcategory"),
                    primaryPlaceholder: L10n.text("medical_record.forms.exam_report.lab.placeholder.primary"),
                    secondaryPlaceholder: L10n.text("medical_record.forms.exam_report.lab.placeholder.subcategory"),
                    primaryRequired: false,
                    secondaryRequired: false,
                    primary: $draft.optionalField(\.category),
                    secondary: $draft.optionalField(\.subCategory),
                    keyboardVisible: $sheetKeyboardVisible
                )
            }
            .padding(.horizontal, 16)
            .onAppear {
                seedLabUnitIfNeeded()
                seedLabFlagIfNeeded()
                reconcileDraftCategoryDefaultsIfNeeded()
            }
        }
    }

    private var labUnitSections: [(header: String?, options: [String])] {
        [
            (L10n.text("medical_record.forms.lab_item.unit_section_common"), sparkLabCommonUnits),
            (L10n.text("medical_record.forms.lab_item.unit_section_more"), sparkLabMoreUnits)
        ]
    }

    private var labFlagSections: [(header: String?, options: [String])] {
        [(nil, SparkLabResultFlag.allCases.map(\.storageString))]
    }

    private var labFlagText: Binding<String> {
        Binding(
            get: {
                let t = (draft.flag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.isEmpty == false else { return SparkLabResultFlag.normal.storageString }
                return SparkLabResultFlag.isPredefinedStoredValue(t)
                    ? SparkLabResultFlag.fromStoredFlag(t).storageString
                    : draft.flag ?? ""
            },
            set: { draft.flag = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        )
    }

    private func seedLabUnitIfNeeded() {
        let u = (draft.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty {
            draft.unit = sparkLabCommonUnits.first ?? "g/L"
        }
    }

    private func seedLabFlagIfNeeded() {
        let t = (draft.flag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            draft.flag = SparkLabResultFlag.normal.storageString
        }
    }

    private var labUnitRow: some View {
        SparkFormMenuCustomRow(
            title: L10n.text("medical_record.forms.field.unit"),
            required: true,
            sections: labUnitSections,
            text: $draft.optionalField(\.unit),
            customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
            customPlaceholder: L10n.text("medical_record.forms.lab_item.unit_custom_placeholder"),
            keyboardVisible: $sheetKeyboardVisible,
            customAutofocus: true
        )
    }

    private var labFlagRow: some View {
        SparkFormMenuCustomRow(
            title: L10n.text("medical_record.forms.lab_item.field.flag"),
            required: true,
            sections: labFlagSections,
            text: labFlagText,
            customMenuTitle: L10n.text("medical_record.forms.lab_item.flag_custom_menu"),
            customPlaceholder: L10n.text("medical_record.forms.lab_item.flag_custom_placeholder"),
            keyboardVisible: $sheetKeyboardVisible,
            optionSystemImage: { option in
                SparkLabResultFlag.allCases.first { $0.storageString == option }?.symbol
            },
            customAutofocus: true
        )
    }

    /// 表单顶部已选一级、二级时带入子项；子项空则填该一级下第一个预设（可改）。
    private func reconcileDraftCategoryDefaultsIfNeeded() {
        let p = (draft.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = LabExamCategoryTaxonomy.resolvedCatalogPrimaryCN(p) else { return }
        let kids = LabExamCategoryTaxonomy.subcategories(for: pCN)
        let s = (draft.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty, let first = kids.first {
            draft.subCategory = first
            return
        }
        if kids.contains(s) { return }
        if let normalized = LabExamCategoryTaxonomy.resolvedCatalogSubcategoryCN(primaryCN: pCN, raw: s) {
            draft.subCategory = normalized
        }
    }

    private func submitDraft() {
        formLog.info("AddLabItemSheet: submit item=\((draft.itemName ?? "").prefix(60))", module: formLogModule)
        onSubmit(draft)
    }
}
