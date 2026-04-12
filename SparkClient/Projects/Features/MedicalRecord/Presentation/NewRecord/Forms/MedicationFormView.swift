import SwiftUI

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

    init(mode: Mode, onCreateSubmit: ((MedicationRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((MedicationRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: MedicationRecognitionDraft
        switch mode {
        case .create:
            seed = .init(genericName: nil, brandName: nil, drugName: nil, dosageForm: nil, strength: nil, route: nil, dosePerTime: nil, doseValue: nil, doseUnit: nil, frequencyCode: nil, period: nil, timesPerPeriod: nil, frequencyText: nil, durationDays: nil, instructions: nil, reminderEnabled: false, reminderTimes: [], sortOrder: "0", extra: nil)
        case .serverEdit(let existing), .localEdit(let existing, _):
            seed = existing
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
                SparkFormTextRow(title: "药名", text: $drugName)
                SparkFormTextRow(title: "通用名", text: $genericName)
                SparkFormTextRow(title: "商品名", text: $brandName)
                SparkFormTextRow(title: "剂型", text: $dosageForm)
                SparkFormTextRow(title: "规格", text: $strength)
                SparkFormTextRow(title: "给药途径", text: $route)
                SparkFormTextRow(title: "每次剂量", text: $dosePerTime)
                SparkFormTextRow(title: "剂量值", text: $doseValue)
                SparkFormTextRow(title: "剂量单位", text: $doseUnit)
                SparkFormTextRow(title: "频次编码", text: $frequencyCode)
                SparkFormTextRow(title: "周期", text: $period)
                SparkFormTextRow(title: "周期次数", text: $timesPerPeriod)
                SparkFormTextRow(title: "频次文案", text: $frequencyText)
                SparkFormTextRow(title: "疗程天数", text: $durationDays)
                SparkFormTextAreaRow(title: "说明", text: $instructions)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "新增用药"; case .serverEdit: return "编辑用药"; case .localEdit: return "编辑用药（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }
    private var outputDraft: MedicationRecognitionDraft {
        .init(genericName: genericName.nilIfBlank, brandName: brandName.nilIfBlank, drugName: drugName.nilIfBlank, dosageForm: dosageForm.nilIfBlank, strength: strength.nilIfBlank, route: route.nilIfBlank, dosePerTime: dosePerTime.nilIfBlank, doseValue: doseValue.nilIfBlank, doseUnit: doseUnit.nilIfBlank, frequencyCode: frequencyCode.nilIfBlank, period: period.nilIfBlank, timesPerPeriod: timesPerPeriod.nilIfBlank, frequencyText: frequencyText.nilIfBlank, durationDays: durationDays.nilIfBlank, instructions: instructions.nilIfBlank, reminderEnabled: false, reminderTimes: [], sortOrder: "0", extra: nil)
    }

    private func saveNow() {
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit): onSubmit(draft); dismiss()
        case .create:
            guard let onCreateSubmit else { dismiss(); return }
            isSaving = true
            Task { do { try await onCreateSubmit(draft); await MainActor.run { dismiss() } } catch { await MainActor.run { errorMessage = error.localizedDescription } }; await MainActor.run { isSaving = false } }
        case .serverEdit:
            guard let onServerSubmit else { dismiss(); return }
            isSaving = true
            Task { do { try await onServerSubmit(draft); await MainActor.run { dismiss() } } catch { await MainActor.run { errorMessage = error.localizedDescription } }; await MainActor.run { isSaving = false } }
        }
    }
}
