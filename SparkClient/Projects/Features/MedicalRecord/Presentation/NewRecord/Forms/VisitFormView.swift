import SwiftUI

/// 就诊记录识别草稿。
struct VisitFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: VisitRecognitionDraft)
        case localEdit(existing: VisitRecognitionDraft, onSubmit: (VisitRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((VisitRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((VisitRecognitionDraft) async throws -> Void)?

    @State private var visitType = ""
    @State private var visitedAt = ""
    @State private var department = ""
    @State private var doctorName = ""
    @State private var visitNo = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(mode: Mode, onCreateSubmit: ((VisitRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((VisitRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: VisitRecognitionDraft
        switch mode {
        case .create: seed = .init(visitType: nil, visitedAt: nil, department: nil, doctorName: nil, visitNo: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _visitType = State(initialValue: seed.visitType ?? "")
        _visitedAt = State(initialValue: seed.visitedAt ?? "")
        _department = State(initialValue: seed.department ?? "")
        _doctorName = State(initialValue: seed.doctorName ?? "")
        _visitNo = State(initialValue: seed.visitNo ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.visit_type"), text: $visitType)
                SparkFormTextRow(
                    title: L10n.text("medical_record.forms.field.visited_at"),
                    text: $visitedAt,
                    placeholder: L10n.text("medical_record.forms.field.date_placeholder")
                )
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.department"), text: $department)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.doctor_name"), text: $doctorName)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.visit_no"), text: $visitNo)
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
                formLog.info("VisitFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.visit.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.visit.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.visit.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("medical_record.forms.action.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("medical_record.forms.action.complete")
        }
    }

    private var outputDraft: VisitRecognitionDraft {
        .init(visitType: visitType.nilIfBlank, visitedAt: visitedAt.nilIfBlank, department: department.nilIfBlank, doctorName: doctorName.nilIfBlank, visitNo: visitNo.nilIfBlank, notes: notes.nilIfBlank)
    }

    private func saveNow() {
        formLog.info("VisitFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("VisitFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("VisitFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onCreateSubmit(draft)
                    await MainActor.run {
                        formLog.info("VisitFormView: create save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("VisitFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("VisitFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onServerSubmit(draft)
                    await MainActor.run {
                        formLog.info("VisitFormView: server save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("VisitFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        }
    }
}
