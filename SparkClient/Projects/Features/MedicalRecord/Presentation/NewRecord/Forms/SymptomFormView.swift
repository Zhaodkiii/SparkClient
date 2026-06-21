import SwiftUI

/// 症状录入/编辑表单：支持成员独立症状（无病历）与病历内症状。
struct SymptomFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteSymptom)
        case localEdit(existing: SymptomRecognitionDraft, onSubmit: (SymptomRecognitionDraft) -> Void)
    }

    struct CreateContext {
        let memberID: Int
        let medicalCaseID: Int?
        let submissionService: MedicalRecordFormSubmissionService
        let onCreateSubmit: MainActorThrowingAction<SymptomRecognitionDraft>?
        let onSaved: (([SparkMedicalSyncAPI.RemoteSymptom], String) -> Void)?
        let onMutation: ((SparkMedicalSyncAPI.SymptomMutationResponse) -> Void)?

        init(
            memberID: Int,
            medicalCaseID: Int? = nil,
            submissionService: MedicalRecordFormSubmissionService,
            onCreateSubmit: MainActorThrowingAction<SymptomRecognitionDraft>? = nil,
            onSaved: (([SparkMedicalSyncAPI.RemoteSymptom], String) -> Void)? = nil,
            onMutation: ((SparkMedicalSyncAPI.SymptomMutationResponse) -> Void)? = nil
        ) {
            self.memberID = memberID
            self.medicalCaseID = medicalCaseID
            self.submissionService = submissionService
            self.onCreateSubmit = onCreateSubmit
            self.onSaved = onSaved
            self.onMutation = onMutation
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onServerSubmit: MainActorThrowingAction<SymptomRecognitionDraft>?

    @State private var selectedSymptoms: [String]
    @State private var duration: String
    @State private var severity: String
    @State private var notes: String
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical
    private let seedDraft: SymptomRecognitionDraft?

    init(mode: Mode, onServerSubmit: MainActorThrowingAction<SymptomRecognitionDraft>? = nil) {
        self.mode = mode
        self.onServerSubmit = onServerSubmit

        let seed: SymptomRecognitionDraft?
        switch mode {
        case .create:
            seed = nil
        case .serverEdit(let existing):
            seed = MedicalCaseTimelineRemoteMapping.symptomDraft(from: existing)
        case .localEdit(let existing, _):
            seed = existing
        }

        self.seedDraft = seed
        _selectedSymptoms = State(initialValue: seed.map(SymptomFormSupport.selectedSymptoms(from:)) ?? [])
        _duration = State(initialValue: seed.map {
            SymptomFormSupport.durationOption(
                value: $0.durationValue.flatMap { Int($0) },
                unit: $0.durationUnit
            )
        } ?? "")
        _severity = State(initialValue: seed?.severity ?? "")
        _notes = State(initialValue: seed?.notes ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                symptomSearchField
                symptomCategoryGroups
                if selectedSymptoms.isEmpty == false {
                    followUpDetailsCard
                }
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: canSubmit && !isSaving,
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

    private var canSubmit: Bool {
        selectedSymptoms.isEmpty == false
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
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    private var symptomSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索症状 (支持拼音/首字母)", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var symptomCategoryGroups: some View {
        VStack(spacing: 0) {
            ForEach(Array(SymptomFormSupport.filteredCategories(matching: searchText).enumerated()), id: \.element.id) { index, category in
                VStack(alignment: .leading, spacing: 10) {
                    Label(category.title, systemImage: category.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(category.symptoms, id: \.self) { symptom in
                            symptomChip(symptom)
                        }
                    }
                }
                .padding(.vertical, 12)

                if index < SymptomFormSupport.filteredCategories(matching: searchText).count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var followUpDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("随访详情与备注")
                .font(.headline)

            detailRow(title: "症状持续时间") {
                Menu {
                    ForEach(SymptomFormSupport.durationOptions, id: \.self) { option in
                        Button(option) { duration = option }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(duration.isEmpty ? "请选择" : duration)
                            .foregroundStyle(duration.isEmpty ? .secondary : .primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("严重程度评估")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                severityPicker
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("补充描述 (例如：特定时间发作、诱因等)...", systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SparkFormTextAreaRow(
                    title: L10n.text("补充描述 (例如：特定时间发作、诱因等)...", fallback: "补充描述 (例如：特定时间发作、诱因等)..."),
                    text: $notes,
                    minHeight: 88,
                    placeholder: L10n.text("medical_record.forms.medical_case.placeholder.chief_complaint"),
                    required: false
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var severityPicker: some View {
        HStack(spacing: 10) {
            severityChoice(title: "轻", value: "low", tint: .green)
            severityChoice(title: "中", value: "medium", tint: .yellow)
            severityChoice(title: "重", value: "high", tint: .red)
        }
    }

    private func detailRow<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
    }

    private func symptomChip(_ symptom: String) -> some View {
        let isSelected = selectedSymptoms.contains(symptom)
        return Button {
            toggle(symptom)
        } label: {
            Text(symptom)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func severityChoice(title: String, value: String, tint: Color) -> some View {
        let isSelected = severity == value
        return Button {
            severity = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ symptom: String) {
        if selectedSymptoms.contains(symptom) {
            selectedSymptoms.removeAll { $0 == symptom }
        } else {
            selectedSymptoms.append(symptom)
        }
    }

    private func saveNow() {
        formLog.info("SymptomFormView: save started mode=\(modeLogLabel)", module: formLogModule)

        switch mode {
        case .localEdit(let existing, let onSubmit):
            guard let draft = outputDraft else {
                errorMessage = "请至少选择一个症状"
                return
            }
            onSubmit(draft)
            formLog.info("SymptomFormView: local submit finished", module: formLogModule)
            dismiss()

        case .serverEdit:
            guard let draft = outputDraft else {
                errorMessage = "请至少选择一个症状"
                return
            }
            guard let onServerSubmit else {
                formLog.warning("SymptomFormView: server handler missing", module: formLogModule)
                dismiss()
                return
            }
            isSaving = true
            Task { @MainActor in
                do {
                    try await onServerSubmit.call(draft)
                    formLog.info("SymptomFormView: server save succeeded", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SymptomFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }

        case .create(let context):
            guard let draft = outputDraft else {
                errorMessage = "请至少选择一个症状"
                return
            }

            isSaving = true
            Task { @MainActor in
                do {
                    var saved: [SparkMedicalSyncAPI.RemoteSymptom] = []
                    var mutation: SparkMedicalSyncAPI.SymptomMutationResponse?
                    if let onCreateSubmit = context.onCreateSubmit {
                        try await onCreateSubmit.call(draft)
                    } else {
                        let response = try await context.submissionService.submitSymptomCreate(
                            memberID: context.memberID,
                            medicalCaseID: context.medicalCaseID,
                            draft: draft
                        )
                        mutation = response
                        if let created = response.symptom {
                            saved = [created]
                        }
                    }

                    let summary = mutation?.summary?.nilIfBlank ?? currentSummaryDescription()
                    context.onSaved?(saved, summary)
                    if let mutation {
                        context.onMutation?(mutation)
                    }
                    formLog.info("SymptomFormView: create save succeeded count=\(saved.count)", module: formLogModule)
                    dismiss()
                } catch {
                    formLog.error("SymptomFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }

    private var outputDraft: SymptomRecognitionDraft? {
        SymptomFormSupport.makeDraft(
            selectedSymptoms: selectedSymptoms,
            duration: duration,
            severity: severity,
            notes: notes,
            existing: seedDraft
        )
    }

    private func currentSummaryDescription() -> String {
        SymptomFormSupport.summaryLine(
            names: selectedSymptoms,
            duration: duration,
            severity: severity,
            notes: notes
        )
    }
}
