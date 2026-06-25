import SwiftUI

/// 处方 + 多条用药计划：用于批量录入 `PrescriptionRecognitionDraft`。
struct MedicationMultiCreateView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemotePrescription)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    struct CreateContext {
        let memberID: Int
        let medicalCaseID: Int?
        let submissionService: MedicalRecordFormSubmissionService

        init(
            memberID: Int,
            medicalCaseID: Int? = nil,
            submissionService: MedicalRecordFormSubmissionService
        ) {
            self.memberID = memberID
            self.medicalCaseID = medicalCaseID
            self.submissionService = submissionService
        }
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
    let submissionService: MedicalRecordFormSubmissionService?
    let memberID: Int?
    let onPrescriptionUpdated: ((SparkMedicalSyncAPI.RemotePrescription) -> Void)?

    @State private var prescriberName = ""
    @State private var institutionName = ""
    @State private var prescribedAt = ""
    @State private var diagnosis = ""
    @State private var prescriptionNo = ""
    @State private var status = "active"
    @State private var items: [MedicationItemDraft] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    /// 创建模式为 `nil`；编辑模式保留病例关联，避免保存时丢失 `medical_case`。
    private let seedMedicalCase: Int?

    init(
        mode: Mode,
        submissionService: MedicalRecordFormSubmissionService? = nil,
        memberID: Int? = nil,
        onPrescriptionUpdated: ((SparkMedicalSyncAPI.RemotePrescription) -> Void)? = nil
    ) {
        self.mode = mode
        self.submissionService = submissionService
        self.memberID = memberID
        self.onPrescriptionUpdated = onPrescriptionUpdated

        let seedMedicalCase: Int?
        switch mode {
        case .create(let context):
            seedMedicalCase = context.medicalCaseID
            _prescriberName = State(initialValue: "")
            _institutionName = State(initialValue: "")
            _prescribedAt = State(initialValue: "")
            _diagnosis = State(initialValue: "")
            _prescriptionNo = State(initialValue: "")
            _status = State(initialValue: "active")
            _items = State(initialValue: [])
        case .serverEdit(let existing):
            seedMedicalCase = existing.medicalCase
            _prescriberName = State(initialValue: existing.prescriberName)
            _institutionName = State(initialValue: existing.institutionName)
            _prescribedAt = State(initialValue: existing.prescribedAt.map { MedicalDateCoding.encodeDateOnly($0) } ?? "")
            _diagnosis = State(initialValue: existing.diagnosis)
            _prescriptionNo = State(initialValue: existing.prescriptionNo ?? "")
            _status = State(initialValue: existing.status)
            _items = State(initialValue: [])
        case .localEdit(let existing, _):
            seedMedicalCase = existing.medicalCase
            _prescriberName = State(initialValue: existing.prescriberName ?? "")
            _institutionName = State(initialValue: existing.institutionName ?? "")
            _prescribedAt = State(initialValue: existing.prescribedAt ?? "")
            _diagnosis = State(initialValue: existing.diagnosis ?? "")
            _prescriptionNo = State(initialValue: existing.prescriptionNo ?? "")
            _status = State(initialValue: existing.status ?? "active")
            _items = State(initialValue: (existing.medicationPlans ?? []).map {
                MedicationItemDraft(
                    medicineName: $0.medicineName ?? $0.medicineBox?.medicineName ?? $0.brandName ?? "",
                    medicineType: $0.medicineType ?? $0.medicineBox?.medicineType ?? "",
                    strength: $0.strength ?? "",
                    frequencyText: $0.frequencyText ?? "",
                    dosePerTime: $0.dosePerTime ?? ""
                )
            })
        }
        self.seedMedicalCase = seedMedicalCase
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: L10n.text("medical_record.forms.prescription_batch.card")) {
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescriber"), text: $prescriberName)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.institution"), text: $institutionName)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescribed_at"), text: $prescribedAt)
                    SparkFormTextRow(title: L10n.text("common.diagnosis"), text: $diagnosis)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.batch_no"), text: $prescriptionNo)
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
            onSave: { Task { await saveNow() } }
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
                frequencyText: item.frequencyText.nilIfBlank,
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
            prescriptionNo: prescriptionNo.nilIfBlank,
            status: status.nilIfBlank,
            extra: nil,
            medicationPlans: meds
        )
    }

    @MainActor
    private func saveNow() async {
        formLog.info("MedicationMultiCreateView: save started mode=\(modeLogLabel) medRows=\(items.count)", module: formLogModule)
        let draft = outputDraft

        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("MedicationMultiCreateView: local submit finished", module: formLogModule)
            dismiss()

        case .serverEdit(let existing):
            guard let submissionService, let memberID else {
                formLog.warning("MedicationMultiCreateView: server submit config missing", module: formLogModule)
                errorMessage = L10n.text("medical_record.forms.error.submit_failed")
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let updated = try await submissionService.submitPrescriptionUpdate(
                    memberID: memberID,
                    existing: existing,
                    draft: draft
                )
                onPrescriptionUpdated?(updated)
                formLog.info("MedicationMultiCreateView: server save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("MedicationMultiCreateView: server save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }

        case .create(let context):
            isSaving = true
            defer { isSaving = false }
            do {
                _ = try await context.submissionService.submitPrescriptionCreate(
                    memberID: context.memberID,
                    medicalCaseID: context.medicalCaseID,
                    draft: draft
                )
                formLog.info("MedicationMultiCreateView: create save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("MedicationMultiCreateView: create save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }
        }
    }
}
