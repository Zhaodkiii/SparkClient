import SwiftUI

/// 单条用药识别草稿：字段与 `MedicationPlanRecognitionDraft` 对齐。
struct MedicationFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: MedicationPlanRecognitionDraft)
        case localEdit(existing: MedicationPlanRecognitionDraft, onSubmit: (MedicationPlanRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: (@MainActor (MedicationPlanRecognitionDraft) async throws -> Void)?
    let onServerSubmit: (@MainActor (MedicationPlanRecognitionDraft) async throws -> Void)?

    @State private var medicineName = ""
    @State private var medicineType = ""
    @State private var brandName = ""
    @State private var dosageForm = ""
    @State private var strength = ""
    @State private var totalQuantity = ""
    @State private var expireDate = ""
    @State private var dosePerTime = ""
    @State private var doseValue = ""
    @State private var doseUnit = ""
    @State private var frequencyCode = ""
    @State private var frequencyType = "daily"
    @State private var timesPerPeriod = ""
    @State private var frequencyText = ""
    @State private var durationDays = ""
    @State private var startDate = ""
    @State private var endDate = ""
    @State private var instructions = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    private let seedSortOrder: String

    init(mode: Mode, onCreateSubmit: (@MainActor (MedicationPlanRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: (@MainActor (MedicationPlanRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: MedicationPlanRecognitionDraft
        switch mode {
        case .create:
            seed = .init(medicineName: nil, medicineType: nil, totalQuantity: nil, expireDate: nil, brandName: nil, dosageForm: nil, strength: nil, dosePerTime: nil, doseValue: nil, doseUnit: nil, frequencyCode: nil, frequencyType: "daily", timesPerPeriod: nil, frequencyText: nil, durationDays: nil, startDate: nil, endDate: nil, instructions: nil, reminderEnabled: false, reminderTimes: [], sortOrder: "0", extra: nil)
            seedSortOrder = "0"
        case .serverEdit(let existing), .localEdit(let existing, _):
            seed = existing
            seedSortOrder = existing.sortOrder ?? "0"
        }

        _medicineName = State(initialValue: seed.medicineName ?? seed.medicineBox?.medicineName ?? seed.brandName ?? "")
        _medicineType = State(initialValue: seed.medicineType ?? seed.medicineBox?.medicineType ?? "")
        _brandName = State(initialValue: seed.brandName ?? "")
        _dosageForm = State(initialValue: seed.dosageForm ?? "")
        _strength = State(initialValue: seed.strength ?? "")
        _totalQuantity = State(initialValue: seed.totalQuantity ?? seed.medicineBox?.totalQuantity ?? "")
        _expireDate = State(initialValue: seed.expireDate ?? seed.medicineBox?.expireDate ?? "")
        _dosePerTime = State(initialValue: seed.dosePerTime ?? "")
        _doseValue = State(initialValue: seed.doseValue ?? "")
        _doseUnit = State(initialValue: seed.doseUnit ?? "")
        _frequencyCode = State(initialValue: seed.frequencyCode ?? "")
        _frequencyType = State(initialValue: seed.frequencyType ?? "daily")
        _timesPerPeriod = State(initialValue: seed.timesPerPeriod ?? "")
        _frequencyText = State(initialValue: seed.frequencyText ?? "")
        _durationDays = State(initialValue: seed.durationDays ?? "")
        _startDate = State(initialValue: seed.startDate ?? "")
        _endDate = State(initialValue: seed.endDate ?? "")
        _instructions = State(initialValue: seed.instructions ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.name", fallback: "药品名称"), text: $medicineName)
                SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.type", fallback: "药品类型"), text: $medicineType)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.brand_name"), text: $brandName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dosage_form"), text: $dosageForm)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.strength"), text: $strength)
                SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.total_quantity", fallback: "总数量"), text: $totalQuantity)
                SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.expire_date", fallback: "有效期"), text: $expireDate)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_per_time"), text: $dosePerTime)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_value"), text: $doseValue)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_unit"), text: $doseUnit)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.frequency_code"), text: $frequencyCode)
                SparkFormTextRow(title: L10n.text("home.medical.list.medication_plan.field.frequency_type", fallback: "频次类型"), text: $frequencyType)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.times_per_period"), text: $timesPerPeriod)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.frequency_text"), text: $frequencyText)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.duration_days"), text: $durationDays)
                SparkFormTextRow(title: L10n.text("home.medical.list.medication_plan.field.start_date", fallback: "开始日期"), text: $startDate)
                SparkFormTextRow(title: L10n.text("home.medical.list.medication_plan.field.end_date", fallback: "结束日期"), text: $endDate)
                SparkFormTextAreaRow(title: L10n.text("medical_record.forms.field.instructions"), text: $instructions)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("MedicationFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                dismiss()
            },
            onSave: { saveNow() }
        )
        .alert(L10n.text("medical_record.forms.error.submit_failed"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var modeLogLabel: String {
        switch mode {
        case .create: return "create"
        case .serverEdit: return "serverEdit"
        case .localEdit: return "localEdit"
        }
    }

    private var navTitle: String {
        switch mode {
        case .create: return L10n.text("medical_record.forms.medication.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.medication.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.medication.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var outputDraft: MedicationPlanRecognitionDraft {
        .init(medicineName: medicineName.nilIfBlank, medicineType: medicineType.nilIfBlank, totalQuantity: totalQuantity.nilIfBlank, expireDate: expireDate.nilIfBlank, brandName: brandName.nilIfBlank, dosageForm: dosageForm.nilIfBlank, strength: strength.nilIfBlank, dosePerTime: dosePerTime.nilIfBlank, doseValue: doseValue.nilIfBlank, doseUnit: doseUnit.nilIfBlank, frequencyCode: frequencyCode.nilIfBlank, frequencyType: frequencyType.nilIfBlank, timesPerPeriod: timesPerPeriod.nilIfBlank, frequencyText: frequencyText.nilIfBlank, durationDays: durationDays.nilIfBlank, startDate: startDate.nilIfBlank, endDate: endDate.nilIfBlank, instructions: instructions.nilIfBlank, reminderEnabled: false, reminderTimes: [], sortOrder: seedSortOrder, extra: nil)
    }

    private func saveNow() {
        formLog.info("MedicationFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("MedicationFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("MedicationFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onCreateSubmit(draft)
                    formLog.info("MedicationFormView: create save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("MedicationFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("MedicationFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onServerSubmit(draft)
                    formLog.info("MedicationFormView: server save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("MedicationFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }
}
