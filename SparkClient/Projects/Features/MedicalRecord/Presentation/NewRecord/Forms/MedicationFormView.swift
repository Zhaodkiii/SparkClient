import SwiftUI

/// 单条用药识别草稿：字段与 `MedicationRecognitionDraft` 对齐。
struct MedicationFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: MedicationRecognitionDraft)
        case localEdit(existing: MedicationRecognitionDraft, onSubmit: (MedicationRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((MedicationRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((MedicationRecognitionDraft) async throws -> Void)?

    @State private var drugName = ""
    @State private var genericName = ""
    @State private var brandName = ""
    @State private var dosageForm = ""
    @State private var strength = ""
    @State private var route = ""
    @State private var dosePerTime = ""
    @State private var doseValue = ""
    @State private var doseUnit = ""
    @State private var frequencyCode = ""
    @State private var period = ""
    @State private var timesPerPeriod = ""
    @State private var frequencyText = ""
    @State private var durationDays = ""
    @State private var instructions = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    private let seedSortOrder: String

    init(mode: Mode, onCreateSubmit: ((MedicationRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((MedicationRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: MedicationRecognitionDraft
        switch mode {
        case .create:
            seed = .init(genericName: nil, brandName: nil, drugName: nil, dosageForm: nil, strength: nil, route: nil, dosePerTime: nil, doseValue: nil, doseUnit: nil, frequencyCode: nil, period: nil, timesPerPeriod: nil, frequencyText: nil, durationDays: nil, instructions: nil, reminderEnabled: false, reminderTimes: [], sortOrder: "0", extra: nil)
            seedSortOrder = "0"
        case .serverEdit(let existing), .localEdit(let existing, _):
            seed = existing
            seedSortOrder = existing.sortOrder ?? "0"
        }

        _drugName = State(initialValue: seed.drugName ?? "")
        _genericName = State(initialValue: seed.genericName ?? "")
        _brandName = State(initialValue: seed.brandName ?? "")
        _dosageForm = State(initialValue: seed.dosageForm ?? "")
        _strength = State(initialValue: seed.strength ?? "")
        _route = State(initialValue: seed.route ?? "")
        _dosePerTime = State(initialValue: seed.dosePerTime ?? "")
        _doseValue = State(initialValue: seed.doseValue ?? "")
        _doseUnit = State(initialValue: seed.doseUnit ?? "")
        _frequencyCode = State(initialValue: seed.frequencyCode ?? "")
        _period = State(initialValue: seed.period ?? "")
        _timesPerPeriod = State(initialValue: seed.timesPerPeriod ?? "")
        _frequencyText = State(initialValue: seed.frequencyText ?? "")
        _durationDays = State(initialValue: seed.durationDays ?? "")
        _instructions = State(initialValue: seed.instructions ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.drug_name"), text: $drugName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.generic_name"), text: $genericName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.brand_name"), text: $brandName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dosage_form"), text: $dosageForm)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.strength"), text: $strength)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.route"), text: $route)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_per_time"), text: $dosePerTime)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_value"), text: $doseValue)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_unit"), text: $doseUnit)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.frequency_code"), text: $frequencyCode)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.period"), text: $period)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.times_per_period"), text: $timesPerPeriod)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.frequency_text"), text: $frequencyText)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.duration_days"), text: $durationDays)
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
        case .create: return L10n.text("medical_record.forms.action.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("medical_record.forms.action.complete")
        }
    }

    private var outputDraft: MedicationRecognitionDraft {
        .init(genericName: genericName.nilIfBlank, brandName: brandName.nilIfBlank, drugName: drugName.nilIfBlank, dosageForm: dosageForm.nilIfBlank, strength: strength.nilIfBlank, route: route.nilIfBlank, dosePerTime: dosePerTime.nilIfBlank, doseValue: doseValue.nilIfBlank, doseUnit: doseUnit.nilIfBlank, frequencyCode: frequencyCode.nilIfBlank, period: period.nilIfBlank, timesPerPeriod: timesPerPeriod.nilIfBlank, frequencyText: frequencyText.nilIfBlank, durationDays: durationDays.nilIfBlank, instructions: instructions.nilIfBlank, reminderEnabled: false, reminderTimes: [], sortOrder: seedSortOrder, extra: nil)
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
            Task {
                do {
                    try await onCreateSubmit(draft)
                    await MainActor.run {
                        formLog.info("MedicationFormView: create save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("MedicationFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("MedicationFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onServerSubmit(draft)
                    await MainActor.run {
                        formLog.info("MedicationFormView: server save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("MedicationFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        }
    }
}
