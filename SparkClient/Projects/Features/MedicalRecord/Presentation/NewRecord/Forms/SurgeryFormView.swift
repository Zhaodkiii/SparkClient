import SwiftUI

/// 手术记录识别草稿。
struct SurgeryFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SurgeryRecognitionDraft)
        case localEdit(existing: SurgeryRecognitionDraft, onSubmit: (SurgeryRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: (@MainActor (SurgeryRecognitionDraft) async throws -> Void)?
    let onServerSubmit: (@MainActor (SurgeryRecognitionDraft) async throws -> Void)?

    @State private var procedureName = ""
    @State private var procedureCode = ""
    @State private var site = ""
    @State private var performedAt = ""
    @State private var surgeon = ""
    @State private var anesthesiaType = ""
    @State private var incisionLevel = ""
    @State private var asaClass = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(mode: Mode, onCreateSubmit: (@MainActor (SurgeryRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: (@MainActor (SurgeryRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: SurgeryRecognitionDraft
        switch mode {
        case .create: seed = .init(procedureName: "", procedureCode: nil, site: nil, performedAt: nil, surgeon: nil, anesthesiaType: nil, incisionLevel: nil, asaClass: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _procedureName = State(initialValue: seed.procedureName)
        _procedureCode = State(initialValue: seed.procedureCode ?? "")
        _site = State(initialValue: seed.site ?? "")
        _performedAt = State(initialValue: seed.performedAt ?? "")
        _surgeon = State(initialValue: seed.surgeon ?? "")
        _anesthesiaType = State(initialValue: seed.anesthesiaType ?? "")
        _incisionLevel = State(initialValue: seed.incisionLevel ?? "")
        _asaClass = State(initialValue: seed.asaClass ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.procedure_name"), text: $procedureName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.procedure_code"), text: $procedureCode)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.site"), text: $site)
                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.field.performed_at"),
                    text: $performedAt,
                    placeholder: L10n.text("medical_record.forms.field.date_placeholder")
                )
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.surgeon"), text: $surgeon)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.anesthesia_type"), text: $anesthesiaType)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.incision_level"), text: $incisionLevel)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.asa_class"), text: $asaClass)
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
                formLog.info("SurgeryFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.surgery.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.surgery.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.surgery.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var outputDraft: SurgeryRecognitionDraft {
        .init(procedureName: procedureName, procedureCode: procedureCode.nilIfBlank, site: site.nilIfBlank, performedAt: performedAt.nilIfBlank, surgeon: surgeon.nilIfBlank, anesthesiaType: anesthesiaType.nilIfBlank, incisionLevel: incisionLevel.nilIfBlank, asaClass: asaClass.nilIfBlank, notes: notes.nilIfBlank)
    }

    private func saveNow() {
        formLog.info("SurgeryFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("SurgeryFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("SurgeryFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onCreateSubmit(draft)
                    formLog.info("SurgeryFormView: create save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SurgeryFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("SurgeryFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onServerSubmit(draft)
                    formLog.info("SurgeryFormView: server save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SurgeryFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }
}
