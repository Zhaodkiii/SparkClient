import SwiftUI

/// 症状识别草稿。
struct SymptomFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SymptomRecognitionDraft)
        case localEdit(existing: SymptomRecognitionDraft, onSubmit: (SymptomRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: (@MainActor (SymptomRecognitionDraft) async throws -> Void)?
    let onServerSubmit: (@MainActor (SymptomRecognitionDraft) async throws -> Void)?

    @State private var name = ""
    @State private var code = ""
    @State private var severity = ""
    @State private var startedAt = ""
    @State private var durationValue = ""
    @State private var durationUnit = ""
    @State private var bodyPart = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(mode: Mode, onCreateSubmit: (@MainActor (SymptomRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: (@MainActor (SymptomRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: SymptomRecognitionDraft
        switch mode {
        case .create: seed = .init(name: "", code: nil, severity: nil, startedAt: nil, durationValue: nil, durationUnit: nil, bodyPart: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _name = State(initialValue: seed.name)
        _code = State(initialValue: seed.code ?? "")
        _severity = State(initialValue: seed.severity ?? "")
        _startedAt = State(initialValue: seed.startedAt ?? "")
        _durationValue = State(initialValue: seed.durationValue ?? "")
        _durationUnit = State(initialValue: seed.durationUnit ?? "")
        _bodyPart = State(initialValue: seed.bodyPart ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.symptom_name"), text: $name)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.symptom_code"), text: $code)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.severity"), text: $severity)
                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.field.started_at"),
                    text: $startedAt,
                    placeholder: L10n.text("medical_record.forms.field.date_placeholder")
                )
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.duration_value"), text: $durationValue)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.duration_unit"), text: $durationUnit)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.body_part"), text: $bodyPart)
                SparkFormTextAreaRow(title: L10n.text("medical_record.forms.field.notes"), text: $notes)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("SymptomFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.symptom.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.symptom.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.symptom.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("medical_record.forms.action.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("medical_record.forms.action.complete")
        }
    }

    private var outputDraft: SymptomRecognitionDraft {
        .init(name: name, code: code.nilIfBlank, severity: severity.nilIfBlank, startedAt: startedAt.nilIfBlank, durationValue: durationValue.nilIfBlank, durationUnit: durationUnit.nilIfBlank, bodyPart: bodyPart.nilIfBlank, notes: notes.nilIfBlank)
    }

    private func saveNow() {
        formLog.info("SymptomFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("SymptomFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("SymptomFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onCreateSubmit(draft)
                    formLog.info("SymptomFormView: create save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SymptomFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("SymptomFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onServerSubmit(draft)
                    formLog.info("SymptomFormView: server save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SymptomFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }
}
