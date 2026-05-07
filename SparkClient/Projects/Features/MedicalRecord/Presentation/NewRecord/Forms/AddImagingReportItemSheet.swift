import SwiftUI

/// 影像检查子项：字段映射 `MedicalReportItem`（`resultValue` 可空，所见+结论写入 `diagnosis`）。
struct AddImagingReportItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let itemID: UUID
    let onSubmit: (ExamReportFormView.ItemDraft) -> Void

    @State private var category: String
    @State private var subCategory: String
    @State private var itemName: String
    @State private var modality: String
    @State private var bodyPart: String
    @State private var resultAt: String
    @State private var diagnosis: String
    @State private var flag: String
    @State private var examAtDay: Date
    @State private var sheetKeyboardVisible = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(draft: ExamReportFormView.ItemDraft, onSubmit: @escaping (ExamReportFormView.ItemDraft) -> Void) {
        self.itemID = draft.id
        self.onSubmit = onSubmit
        _category = State(initialValue: draft.category)
        _subCategory = State(initialValue: draft.subCategory)
        _itemName = State(initialValue: draft.itemName)
        _modality = State(initialValue: draft.modality)
        _bodyPart = State(initialValue: draft.bodyPart)
        let rawAt = draft.resultAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = Self.dayFormatter.date(from: rawAt) ?? Date()
        let resolvedAt = rawAt.isEmpty ? Self.dayFormatter.string(from: day) : rawAt
        _resultAt = State(initialValue: resolvedAt)
        _diagnosis = State(initialValue: draft.diagnosis)
        _flag = State(initialValue: draft.flag)
        _examAtDay = State(initialValue: day)
    }

    private var canSubmit: Bool {
        let nonEmpty: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonEmpty(category)
            && nonEmpty(itemName)
            && nonEmpty(modality)
            && nonEmpty(bodyPart)
            && nonEmpty(diagnosis)
    }

    var body: some View {
        CompatibleNavigationContainer {
            formScroll
                .navigationTitle(L10n.text("medical_record.forms.exam_report.imaging.sheet_title"))
                .navigationBarTitleDisplayMode(.inline)
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("AddImagingReportItemSheet: cancel tapped", module: formLogModule)
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
                Text(L10n.text("medical_record.forms.exam_report.imaging.sheet_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                SparkImagingCategoryCascadeRow(
                    primaryTitle: L10n.text("medical_record.forms.exam_report.imaging.field.category"),
                    secondaryTitle: L10n.text("medical_record.forms.exam_report.imaging.field.subcategory"),
                    primaryPlaceholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.category"),
                    secondaryPlaceholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.subcategory"),
                    primaryRequired: true,
                    secondaryRequired: false,
                    primary: $category,
                    secondary: $subCategory,
                    keyboardVisible: $sheetKeyboardVisible
                )

                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.exam_report.imaging.field.item_name"),
                    text: $itemName,
                    placeholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.item_name"),
                    required: true,
                    keyboardVisible: $sheetKeyboardVisible
                )

                HStack(alignment: .top, spacing: 12) {
                    SparkFormTextRow(
                        title: L10n.text("medical_record.forms.exam_report.imaging.field.modality"),
                        text: $modality,
                        placeholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.modality"),
                        required: true,
                        keyboardVisible: $sheetKeyboardVisible
                    )
                    SparkFormTextRow(
                        title: L10n.text("medical_record.forms.exam_report.imaging.field.body_part"),
                        text: $bodyPart,
                        placeholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.body_part"),
                        required: true,
                        keyboardVisible: $sheetKeyboardVisible
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("medical_record.forms.exam_report.imaging.field.result_at"))
                        .font(.subheadline.weight(.medium))
                    DatePicker("", selection: $examAtDay, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .onChange(of: examAtDay) { newValue in
                            resultAt = Self.dayFormatter.string(from: newValue)
                        }
                }

                SparkFormTextAreaRow(
                    title: L10n.text("medical_record.forms.exam_report.imaging.field.diagnosis"),
                    text: $diagnosis,
                    placeholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.diagnosis"),
                    required: true,
                    keyboardVisible: $sheetKeyboardVisible
                )

                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.exam_report.imaging.field.flag"),
                    text: $flag,
                    placeholder: L10n.text("medical_record.forms.exam_report.imaging.placeholder.flag"),
                    keyboardVisible: $sheetKeyboardVisible
                )
            }
            .padding(.horizontal, 16)
            .onAppear {
                reconcileImagingCategoryDefaultsIfNeeded()
            }
        }
    }

    /// 父级已带一级、二级时对齐中文键；二级空则填该一级下第一个预设。
    private func reconcileImagingCategoryDefaultsIfNeeded() {
        let p = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = ImagingCategoryTaxonomy.resolvedCatalogPrimaryCN(p) else { return }
        let kids = ImagingCategoryTaxonomy.subcategories(for: pCN)
        let s = subCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty, let first = kids.first {
            subCategory = first
            return
        }
        if kids.contains(s) { return }
        if let normalized = ImagingCategoryTaxonomy.resolvedCatalogSubcategoryCN(primaryCN: pCN, raw: s) {
            subCategory = normalized
        }
    }

    private func submitDraft() {
        let at = resultAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.dayFormatter.string(from: examAtDay)
            : resultAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = ExamReportFormView.ItemDraft(
            id: itemID,
            category: category,
            subCategory: subCategory,
            itemName: itemName,
            resultValue: "",
            unit: "",
            referenceRange: "",
            flag: flag,
            modality: modality,
            bodyPart: bodyPart,
            resultAt: at,
            diagnosis: diagnosis
        )
        formLog.info("AddImagingReportItemSheet: submit item=\(itemName.prefix(40))", module: formLogModule)
        onSubmit(out)
    }
}
