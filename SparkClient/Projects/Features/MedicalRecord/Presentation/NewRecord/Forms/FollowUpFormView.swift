import SwiftUI

/// 随访识别草稿表单：新建、服务端更新或仅本地回写。
struct FollowUpFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteFollowUp)
        case localEdit(existing: FollowUpRecognitionDraft, onSubmit: (FollowUpRecognitionDraft) -> Void)
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

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let submissionService: MedicalRecordFormSubmissionService?
    let memberID: Int?

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

    init(
        mode: Mode,
        submissionService: MedicalRecordFormSubmissionService? = nil,
        memberID: Int? = nil
    ) {
        self.mode = mode
        self.submissionService = submissionService
        self.memberID = memberID

        let seed: FollowUpRecognitionDraft
        switch mode {
        case .create:
            seed = .init(plannedAt: nil, completedAt: nil, status: nil, method: nil, outcome: nil, nextAction: nil)
        case .serverEdit(let existing):
            seed = MedicalCaseTimelineRemoteMapping.followUpDraft(from: existing)
        case .localEdit(let existing, _):
            seed = existing
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
                SparkFormTextRow(title: L10n.text("common.status"), text: $status)
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
        case .create: return L10n.text("medical_record.forms.follow_up.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.follow_up.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.follow_up.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var outputDraft: FollowUpRecognitionDraft {
        .init(
            plannedAt: plannedAt.nilIfBlank,
            completedAt: completedAt.nilIfBlank,
            status: status.nilIfBlank,
            method: method.nilIfBlank,
            outcome: outcome.nilIfBlank,
            nextAction: nextAction.nilIfBlank
        )
    }

    @MainActor
    private func saveNow() async {
        formLog.info("FollowUpFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft

        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("FollowUpFormView: local submit finished", module: formLogModule)
            dismiss()

        case .serverEdit(let existing):
            guard let submissionService, let memberID else {
                formLog.warning("FollowUpFormView: server submit config missing", module: formLogModule)
                errorMessage = L10n.text("medical_record.forms.error.submit_failed")
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                try await submissionService.submitFollowUpUpdate(
                    memberID: memberID,
                    existing: existing,
                    draft: draft
                )
                formLog.info("FollowUpFormView: server save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("FollowUpFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }

        case .create(let context):
            isSaving = true
            defer { isSaving = false }
            do {
                _ = try await context.submissionService.submitFollowUpCreate(
                    memberID: context.memberID,
                    medicalCaseID: context.medicalCaseID,
                    draft: draft
                )
                formLog.info("FollowUpFormView: create save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("FollowUpFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }
        }
    }
}
