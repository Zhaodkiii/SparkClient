import SwiftUI

/// 就诊记录录入/编辑表单：支持成员独立就诊（无病历）与病历内就诊。
struct VisitFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteVisit)
        case localEdit(existing: VisitRecognitionDraft, onSubmit: (VisitRecognitionDraft) -> Void)
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

    init(
        mode: Mode,
        submissionService: MedicalRecordFormSubmissionService? = nil,
        memberID: Int? = nil
    ) {
        self.mode = mode
        self.submissionService = submissionService
        self.memberID = memberID

        let seed: VisitRecognitionDraft
        switch mode {
        case .create:
            seed = .init(visitType: nil, visitedAt: nil, department: nil, doctorName: nil, visitNo: nil, notes: nil)
        case .serverEdit(let existing):
            seed = MedicalCaseTimelineRemoteMapping.visitDraft(from: existing)
        case .localEdit(let existing, _):
            seed = existing
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
        case .create: return L10n.text("medical_record.forms.visit.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.visit.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.visit.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var outputDraft: VisitRecognitionDraft {
        .init(
            visitType: visitType.nilIfBlank,
            visitedAt: visitedAt.nilIfBlank,
            department: department.nilIfBlank,
            doctorName: doctorName.nilIfBlank,
            visitNo: visitNo.nilIfBlank,
            notes: notes.nilIfBlank
        )
    }

    @MainActor
    private func saveNow() async {
        formLog.info("VisitFormView: save started mode=\(modeLogLabel)", module: formLogModule)
        let draft = outputDraft

        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("VisitFormView: local submit finished", module: formLogModule)
            dismiss()

        case .serverEdit(let existing):
            guard let submissionService, let memberID else {
                formLog.warning("VisitFormView: server submit config missing", module: formLogModule)
                errorMessage = L10n.text("medical_record.forms.error.submit_failed")
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                try await submissionService.submitVisitUpdate(
                    memberID: memberID,
                    existing: existing,
                    draft: draft
                )
                formLog.info("VisitFormView: server save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("VisitFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }

        case .create(let context):
            isSaving = true
            defer { isSaving = false }
            do {
                _ = try await context.submissionService.submitVisitCreate(
                    memberID: context.memberID,
                    medicalCaseID: context.medicalCaseID,
                    draft: draft
                )
                formLog.info("VisitFormView: create save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("VisitFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }
        }
    }
}
