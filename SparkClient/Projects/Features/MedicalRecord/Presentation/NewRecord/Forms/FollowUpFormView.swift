import SwiftUI

/// 随访识别草稿表单：新建、服务端更新或仅本地回写。
struct FollowUpFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: FollowUpRecognitionDraft)
        case localEdit(existing: FollowUpRecognitionDraft, onSubmit: (FollowUpRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((FollowUpRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((FollowUpRecognitionDraft) async throws -> Void)?

    @State private var plannedAt = ""
    @State private var completedAt = ""
    @State private var status = ""
    @State private var method = ""
    @State private var outcome = ""
    @State private var nextAction = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(mode: Mode, onCreateSubmit: ((FollowUpRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((FollowUpRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: FollowUpRecognitionDraft
        switch mode {
        case .create: seed = .init(plannedAt: nil, completedAt: nil, status: nil, method: nil, outcome: nil, nextAction: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _plannedAt = State(initialValue: seed.plannedAt ?? "")
        _completedAt = State(initialValue: seed.completedAt ?? "")
        _status = State(initialValue: seed.status ?? "")
        _method = State(initialValue: seed.method ?? "")
        _outcome = State(initialValue: seed.outcome ?? "")
        _nextAction = State(initialValue: seed.nextAction ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.planned_time"), text: $plannedAt)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.completed_time"), text: $completedAt)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.status"), text: $status)
                SparkFormTextRow(title: L10n.text("medical_record.forms.field.method"), text: $method)
                SparkFormTextAreaRow(title: L10n.text("medical_record.forms.field.outcome"), text: $outcome)
                SparkFormTextAreaRow(title: L10n.text("medical_record.forms.field.next_plan"), text: $nextAction)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("FollowUpFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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
        case .create: return L10n.text("medical_record.forms.follow_up.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.follow_up.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.follow_up.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("medical_record.forms.action.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("medical_record.forms.action.complete")
        }
    }

    private var outputDraft: FollowUpRecognitionDraft {
        .init(plannedAt: plannedAt.nilIfBlank, completedAt: completedAt.nilIfBlank, status: status.nilIfBlank, method: method.nilIfBlank, outcome: outcome.nilIfBlank, nextAction: nextAction.nilIfBlank)
    }

    private func saveNow() {
        formLog.info("FollowUpFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("FollowUpFormView: local submit finished", module: formLogModule)
            dismiss()
        case .create:
            guard let onCreateSubmit else {
                formLog.warning("FollowUpFormView: create handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onCreateSubmit(draft)
                    await MainActor.run {
                        formLog.info("FollowUpFormView: create save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("FollowUpFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        case .serverEdit:
            guard let onServerSubmit else {
                formLog.warning("FollowUpFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task {
                do {
                    try await onServerSubmit(draft)
                    await MainActor.run {
                        formLog.info("FollowUpFormView: server save succeeded", module: formLogModule)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        formLog.error("FollowUpFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isSaving = false }
            }
        }
    }
}
