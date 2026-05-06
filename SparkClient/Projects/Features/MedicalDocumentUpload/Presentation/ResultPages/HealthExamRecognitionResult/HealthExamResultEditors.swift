import SwiftUI

struct HealthExamBasicInfoEditorView: View {
    let initial: HealthExamRecognitionDraft
    let onSubmit: (HealthExamRecognitionDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var institutionName: String
    @State private var reportNo: String
    @State private var examDate: String
    @State private var examType: String
    @State private var summary: String

    init(initial: HealthExamRecognitionDraft, onSubmit: @escaping (HealthExamRecognitionDraft) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        _institutionName = State(initialValue: initial.institutionName ?? "")
        _reportNo = State(initialValue: initial.reportNo ?? "")
        _examDate = State(initialValue: initial.examDate ?? "")
        _examType = State(initialValue: initial.examType ?? "")
        _summary = State(initialValue: initial.summary ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: L10n.text("medical.upload.result.health_exam.basic_info.edit_title")) {
                    SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.basic_info.institution"), text: $institutionName)
                    SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.basic_info.report_no"), text: $reportNo)
                    SparkFormTextRow(
                        title: L10n.text("medical.upload.result.health_exam.basic_info.exam_date"),
                        text: $examDate,
                        placeholder: L10n.text("medical_record.forms.field.date_placeholder")
                    )
                    SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.basic_info.exam_type"), text: $examType)
                    SparkFormTextAreaRow(title: L10n.text("medical.upload.result.health_exam.basic_info.summary"), text: $summary)
                }
            }
            .padding(16)
        }
        .navigationTitle(L10n.text("medical.upload.result.health_exam.basic_info.nav"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(L10n.text("medical.upload.result.common.back")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("common.done")) {
                    onSubmit(
                        initial.replacingBasicInfo(
                            institutionName: institutionName.nilIfBlank,
                            reportNo: reportNo.nilIfBlank,
                            examDate: examDate.nilIfBlank,
                            examType: examType.nilIfBlank,
                            summary: summary.nilIfBlank
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

struct HealthExamRiskItemEditorView: View {
    let item: MedicalReportItem
    let onSubmit: (MedicalReportItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var category: String
    @State private var subCategory: String
    @State private var itemName: String
    @State private var resultValue: String
    @State private var unit: String
    @State private var referenceRange: String
    @State private var flag: String
    @State private var diagnosis: String

    init(item: MedicalReportItem, onSubmit: @escaping (MedicalReportItem) -> Void) {
        self.item = item
        self.onSubmit = onSubmit
        _category = State(initialValue: item.category)
        _subCategory = State(initialValue: item.subCategory ?? "")
        _itemName = State(initialValue: item.itemName ?? "")
        _resultValue = State(initialValue: item.resultValue ?? "")
        _unit = State(initialValue: item.unit ?? "")
        _referenceRange = State(initialValue: item.referenceRange ?? "")
        _flag = State(initialValue: item.flag ?? "")
        _diagnosis = State(initialValue: item.diagnosis ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: L10n.text("medical.upload.result.health_exam.item.edit_title")) {
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.category"), text: $category)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.subcategory"), text: $subCategory)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.name"), text: $itemName)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.result"), text: $resultValue)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.unit"), text: $unit)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.reference"), text: $referenceRange)
                SparkFormTextRow(title: L10n.text("medical.upload.result.health_exam.item.flag"), text: $flag)
                SparkFormTextAreaRow(title: L10n.text("medical.upload.result.health_exam.item.diagnosis"), text: $diagnosis)
            }
            .padding(16)
        }
        .navigationTitle(L10n.text("medical.upload.result.health_exam.item.nav"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(L10n.text("medical.upload.result.common.back")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("common.done")) {
                    onSubmit(
                        MedicalReportItem(
                            category: category.nilIfBlank ?? item.category,
                            subCategory: subCategory.nilIfBlank,
                            itemName: itemName.nilIfBlank,
                            itemCode: item.itemCode,
                            resultValue: resultValue.nilIfBlank,
                            unit: unit.nilIfBlank,
                            referenceRange: referenceRange.nilIfBlank,
                            flag: flag.nilIfBlank,
                            resultAt: item.resultAt,
                            modality: item.modality,
                            bodyPart: item.bodyPart,
                            diagnosis: diagnosis.nilIfBlank,
                            extra: item.extra,
                            sortOrder: item.sortOrder
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}
