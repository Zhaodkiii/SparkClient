import SwiftUI

/// 手术录入/编辑表单：支持成员独立手术（无病历）与病历内手术。
struct SurgeryFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteSurgery)
        case localEdit(existing: SurgeryRecognitionDraft, onSubmit: (SurgeryRecognitionDraft) -> Void)
    }

    struct CreateContext {
        let memberID: Int
        let medicalCaseID: Int?
        let submissionService: MedicalRecordFormSubmissionService
        let onSaved: (([SparkMedicalSyncAPI.RemoteSurgery], String) -> Void)?
        let onMutation: ((SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void)?

        init(
            memberID: Int,
            medicalCaseID: Int? = nil,
            submissionService: MedicalRecordFormSubmissionService,
            onSaved: (([SparkMedicalSyncAPI.RemoteSurgery], String) -> Void)? = nil,
            onMutation: ((SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void)? = nil
        ) {
            self.memberID = memberID
            self.medicalCaseID = medicalCaseID
            self.submissionService = submissionService
            self.onSaved = onSaved
            self.onMutation = onMutation
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let submissionService: MedicalRecordFormSubmissionService?
    let memberID: Int?
    let onMutation: ((SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void)?

    @State private var procedureName: String
    @State private var performedAt: String
    @State private var recoveryStatus: String
    @State private var hospitalName: String
    @State private var site: String
    @State private var notes: String
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    private let seedDraft: SurgeryRecognitionDraft?

    init(
        mode: Mode,
        submissionService: MedicalRecordFormSubmissionService? = nil,
        memberID: Int? = nil,
        onMutation: ((SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void)? = nil
    ) {
        self.mode = mode
        self.submissionService = submissionService
        self.memberID = memberID
        self.onMutation = onMutation

        let seed: SurgeryRecognitionDraft?
        let initialRecovery: String
        let initialHospital: String
        switch mode {
        case .create:
            seed = nil
            initialRecovery = ""
            initialHospital = ""
        case .serverEdit(let existing):
            seed = MedicalCaseTimelineRemoteMapping.surgeryDraft(from: existing)
            initialRecovery = SurgeryFormSupport.recoveryStatus(for: existing)
            initialHospital = SurgeryFormSupport.hospitalName(for: existing)
            let performedText = SurgeryFormSupport.performedAtText(for: existing)
            _procedureName = State(initialValue: seed?.procedureName ?? "")
            _performedAt = State(initialValue: performedText.nilIfBlank ?? seed?.performedAt ?? "")
            _recoveryStatus = State(initialValue: initialRecovery)
            _hospitalName = State(initialValue: initialHospital)
            _site = State(initialValue: seed?.site ?? "")
            _notes = State(initialValue: seed?.notes ?? "")
            self.seedDraft = seed
            return
        case .localEdit(let existing, _):
            seed = existing
            initialRecovery = ""
            initialHospital = ""
        }

        self.seedDraft = seed
        _procedureName = State(initialValue: seed?.procedureName ?? "")
        _performedAt = State(initialValue: seed?.performedAt ?? "")
        _recoveryStatus = State(initialValue: initialRecovery)
        _hospitalName = State(initialValue: initialHospital)
        _site = State(initialValue: seed?.site ?? "")
        _notes = State(initialValue: seed?.notes ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                surgeryCategoryGroups
                surgeryDetailsCard
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: Text(L10n.text("medical_record.forms.surgery.search_prompt"))
        )
        .sparkFormBottomBar(
            canSubmit: canSubmit && !isSaving,
            saveTitle: saveTitle,
            onCancel: {
                formLog.info("SurgeryFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
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

    private var canSubmit: Bool {
        procedureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var surgeryCategoryGroups: some View {
        VStack(spacing: 0) {
            ForEach(Array(SurgeryFormSupport.filteredCategories(matching: searchText).enumerated()), id: \.element.id) { index, category in
                VStack(alignment: .leading, spacing: 10) {
                    Label(category.title, systemImage: category.systemImage)
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(category.procedures, id: \.self) { name in
                            procedureChip(name)
                        }
                    }
                }
                .padding(.vertical, 8)

                if index != SurgeryFormSupport.filteredCategories(matching: searchText).count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var surgeryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            formTextRow(systemName: "scissors", title: L10n.text("medical_record.forms.surgery.field.name"), placeholder: L10n.text("medical_record.forms.surgery.field.name_placeholder"), text: $procedureName)
            Divider().padding(.leading, 16)
            formTextRow(systemName: "calendar", title: L10n.text("medical_record.forms.surgery.field.date"), placeholder: L10n.text("medical_record.forms.surgery.field.date_placeholder"), text: $performedAt)
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.text("medical_record.forms.surgery.field.recovery"), systemImage: "heart.text.square.fill")
                    .font(.subheadline.weight(.semibold))
                recoveryChipRow
            }
            .padding(.vertical, 12)
            Divider().padding(.leading, 16)
            formTextRow(systemName: "building.2.fill", title: L10n.text("medical_record.forms.surgery.field.hospital"), placeholder: L10n.text("medical_record.forms.surgery.field.optional"), text: $hospitalName)
            Divider().padding(.leading, 16)
            formTextRow(systemName: "mappin.and.ellipse", title: L10n.text("medical_record.forms.surgery.field.site"), placeholder: L10n.text("medical_record.forms.surgery.field.optional"), text: $site)
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.text("medical_record.forms.surgery.field.notes"), systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var recoveryChipRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(SurgeryFormSupport.recoveryOptions, id: \.self) { option in
                recoveryChip(option)
            }
        }
    }

    private func formTextRow(systemName: String, title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 12)
    }

    private func procedureChip(_ name: String) -> some View {
        let isSelected = procedureName == name
        return Button {
            procedureName = name
        } label: {
            Text(SurgeryFormSupport.displayProcedure(name))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func recoveryChip(_ option: String) -> some View {
        let isSelected = recoveryStatus == option
        return Button {
            recoveryStatus = option
        } label: {
            Text(SurgeryFormSupport.displayRecoveryStatus(option))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                )
        }
        .buttonStyle(.plain)
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

    private var outputDraft: SurgeryRecognitionDraft? {
        SurgeryFormSupport.makeDraft(
            procedureName: procedureName,
            performedAt: performedAt,
            recoveryStatus: recoveryStatus,
            hospitalName: hospitalName,
            site: site,
            notes: notes,
            existing: seedDraft
        )
    }

    @MainActor
    private func saveNow() async {
        formLog.info("SurgeryFormView: save started mode=\(modeLogLabel)", module: formLogModule)

        switch mode {
        case .localEdit(_, let onSubmit):
            guard let draft = outputDraft else {
                errorMessage = "请填写手术名称"
                return
            }
            onSubmit(draft)
            dismiss()

        case .serverEdit(let existing):
            guard let draft = outputDraft else {
                errorMessage = "请填写手术名称"
                return
            }
            guard let submissionService, let memberID else {
                formLog.warning("SurgeryFormView: server submit config missing", module: formLogModule)
                errorMessage = L10n.text("medical_record.forms.error.submit_failed")
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let response = try await submissionService.submitSurgeryUpdate(
                    memberID: memberID,
                    existing: existing,
                    draft: draft,
                    recoveryStatus: recoveryStatus,
                    hospitalName: hospitalName
                )
                onMutation?(response)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

        case .create(let context):
            guard let draft = outputDraft else {
                errorMessage = "请填写手术名称"
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let response = try await context.submissionService.submitSurgeryCreate(
                    memberID: context.memberID,
                    medicalCaseID: context.medicalCaseID,
                    draft: draft,
                    recoveryStatus: recoveryStatus,
                    hospitalName: hospitalName
                )
                var saved: [SparkMedicalSyncAPI.RemoteSurgery] = []
                if let created = response.surgery {
                    saved = [created]
                }

                let summary = response.summary?.nilIfBlank ?? SurgeryFormSupport.summaryLine(
                    procedureName: procedureName,
                    performedAt: performedAt,
                    recoveryStatus: recoveryStatus,
                    hospitalName: hospitalName,
                    site: site
                )
                context.onSaved?(saved, summary)
                context.onMutation?(response)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
