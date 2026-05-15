import SwiftUI

/// 处方（无明细用药计划列表）识别草稿。
struct PrescriptionBatchFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: PrescriptionRecognitionDraft)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)?

    @State private var prescriberName = ""
    @State private var institutionName = ""
    @State private var prescribedAt = ""
    @State private var diagnosis = ""
    @State private var prescriptionNo = ""
    @State private var status = "active"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(mode: Mode, onCreateSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: PrescriptionRecognitionDraft
        switch mode {
        case .create:
            seed = .init(medicalCase: nil, prescriberName: nil, institutionName: nil, prescribedAt: nil, diagnosis: nil, prescriptionNo: nil, status: "active", extra: nil, medicationPlans: [])
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }

        _prescriberName = State(initialValue: seed.prescriberName ?? "")
        _institutionName = State(initialValue: seed.institutionName ?? "")
        _prescribedAt = State(initialValue: seed.prescribedAt ?? "")
        _diagnosis = State(initialValue: seed.diagnosis ?? "")
        _prescriptionNo = State(initialValue: seed.prescriptionNo ?? "")
        _status = State(initialValue: seed.status ?? "active")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescriber"), text: $prescriberName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.institution"), text: $institutionName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.prescribed_at"), text: $prescribedAt)
                SparkFormTextRow(title: L10n.text("common.diagnosis"), text: $diagnosis)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.batch_no"), text: $prescriptionNo)
                SparkFormTextRow(title: L10n.text("common.status"), text: $status)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("PrescriptionBatchFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.prescription_batch.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.prescription_batch.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.prescription_batch.title.edit_local")
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
        .init(medicalCase: nil, prescriberName: prescriberName.nilIfBlank, institutionName: institutionName.nilIfBlank, prescribedAt: prescribedAt.nilIfBlank, diagnosis: diagnosis.nilIfBlank, prescriptionNo: prescriptionNo.nilIfBlank, status: status.nilIfBlank, extra: nil, medicationPlans: [])
    }

    private func saveNow() {
        formLog.info("PrescriptionBatchFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("PrescriptionBatchFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("PrescriptionBatchFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onCreateSubmit(draft)
                    await MainActor.run {
                        formLog.info("PrescriptionBatchFormView: create save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("PrescriptionBatchFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("PrescriptionBatchFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onServerSubmit(draft)
                    await MainActor.run {
                        formLog.info("PrescriptionBatchFormView: server save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("PrescriptionBatchFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        }
    }
}
