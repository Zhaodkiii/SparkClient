import SwiftUI

/// 处方批次 + 多条药品行：用于批量录入 `PrescriptionRecognitionDraft`。
struct MedicationMultiCreateView: View {
    enum Mode {
        case create
        case serverEdit(existing: PrescriptionRecognitionDraft)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    struct MedicationItemDraft: Identifiable {
        var id = UUID()
        var medicineName: String = ""
        var medicineType: String = ""
        var strength: String = ""
        var frequencyText: String = ""
        var dosePerTime: String = ""
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: (@MainActor (PrescriptionRecognitionDraft) async throws -> Void)?
    let onServerSubmit: (@MainActor (PrescriptionRecognitionDraft) async throws -> Void)?

    @State private var prescriberName = ""
    @State private var institutionName = ""
    @State private var prescribedAt = ""
    @State private var diagnosis = ""
    @State private var batchNo = ""
    @State private var status = "active"
    @State private var items: [MedicationItemDraft] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    /// 创建模式为 `nil`；编辑模式保留病例关联，避免保存时丢失 `medical_case`。
    private let seedMedicalCase: Int?

    init(mode: Mode, createMedicalCaseID: Int? = nil, onCreateSubmit: (@MainActor (PrescriptionRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: (@MainActor (PrescriptionRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: PrescriptionRecognitionDraft
        switch mode {
        case .create:
            seed = .init(medicalCase: createMedicalCaseID, prescriberName: nil, institutionName: nil, prescribedAt: nil, diagnosis: nil, batchNo: nil, status: "active", auditorName: nil, auditedAt: nil, extra: nil, medications: [])
            seedMedicalCase = createMedicalCaseID
        case .serverEdit(let existing), .localEdit(let existing, _):
            seed = existing
            seedMedicalCase = existing.medicalCase
        }

        _prescriberName = State(initialValue: seed.prescriberName ?? "")
        _institutionName = State(initialValue: seed.institutionName ?? "")
        _prescribedAt = State(initialValue: seed.prescribedAt ?? "")
        _diagnosis = State(initialValue: seed.diagnosis ?? "")
        _batchNo = State(initialValue: seed.batchNo ?? "")
        _status = State(initialValue: seed.status ?? "active")
        _items = State(initialValue: (seed.medications ?? []).map {
            MedicationItemDraft(medicineName: $0.medicineName ?? $0.medicineBox?.medicineName ?? $0.brandName ?? "", medicineType: $0.medicineType ?? $0.medicineBox?.medicineType ?? "", strength: $0.strength ?? "", frequencyText: $0.frequencyText ?? "", dosePerTime: $0.dosePerTime ?? "")
        })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: L10n.text("medical_record.forms.prescription_batch.card")) {
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescriber"), text: $prescriberName)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.institution"), text: $institutionName)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescribed_at"), text: $prescribedAt)
                    SparkFormTextRow(title: L10n.text("common.diagnosis"), text: $diagnosis)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.batch_no"), text: $batchNo)
                    SparkFormTextRow(title: L10n.text("common.status"), text: $status)
                }

                SparkFormCard(title: L10n.text("medical_record.forms.medication_list.card")) {
                    Button(L10n.text("medical_record.forms.medication_list.add_row")) {
                        items.append(.init())
                    }
                    .buttonStyle(.bordered)

                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.name", fallback: "药品名称"), text: $item.medicineName)
                            SparkFormTextRow(title: L10n.text("home.medical.list.medicine_box.field.type", fallback: "药品类型"), text: $item.medicineType)
                            SparkFormTextRow(title: L10n.text("medical_record.forms.field.strength"), text: $item.strength)
                            SparkFormTextRow(title: L10n.text("medical_record.forms.field.frequency_text"), text: $item.frequencyText)
                            SparkFormTextRow(title: L10n.text("medical_record.forms.field.dose_per_time"), text: $item.dosePerTime)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("MedicationMultiCreateView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.medication_multi.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.medication_multi.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.medication_multi.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var outputDraft: PrescriptionRecognitionDraft {
        let meds = items.enumerated().map { index, item in
            MedicationPlanRecognitionDraft(
                medicineName: item.medicineName.nilIfBlank,
                medicineType: item.medicineType.nilIfBlank,
                dosageForm: nil,
                strength: item.strength.nilIfBlank,
                dosePerTime: item.dosePerTime.nilIfBlank,
                doseValue: nil,
                doseUnit: nil,
                frequencyCode: nil,
                timesPerPeriod: nil,
                frequencyText: item.frequencyText.nilIfBlank,
                durationDays: nil,
                instructions: nil,
                reminderEnabled: false,
                reminderTimes: [],
                sortOrder: "\(index)",
                extra: nil
            )
        }
        return .init(
            medicalCase: seedMedicalCase,
            prescriberName: prescriberName.nilIfBlank,
            institutionName: institutionName.nilIfBlank,
            prescribedAt: prescribedAt.nilIfBlank,
            diagnosis: diagnosis.nilIfBlank,
            batchNo: batchNo.nilIfBlank,
            status: status.nilIfBlank,
            auditorName: nil,
            auditedAt: nil,
            extra: nil,
            medications: meds
        )
    }

    private func saveNow() {
        formLog.info("MedicationMultiCreateView: save started mode=\(modeLogLabel) medRows=\(items.count)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("MedicationMultiCreateView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("MedicationMultiCreateView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onCreateSubmit(draft)
                    formLog.info("MedicationMultiCreateView: create save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("MedicationMultiCreateView: create save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("MedicationMultiCreateView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onServerSubmit(draft)
                    formLog.info("MedicationMultiCreateView: server save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("MedicationMultiCreateView: server save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }
}
