import SwiftUI

struct ModelScenarioBindingPersistenceChange {
    var upserted: AIScenarioModelBinding?
    var deletedID: UUID?
}

struct ModelScenarioBindingsEditorView: View {
    @Binding var scenarioBindings: [AIScenarioModelBinding]
    let modelID: UUID
    let identity: AIModelIdentity
    var defaultSystemProvision: String = ""
    var defaultBriefDescription: String = ""
    var defaultToolScenarios: [String] = []
    var defaultRelatedTaskCodes: [String] = []
    var smallTasks: [SmallTask] = []
    var onPersist: ((ModelScenarioBindingPersistenceChange) -> Void)?

    @State private var presentedMode: ModelScenarioBindingEditorMode?

    private var bindings: [AIScenarioModelBinding] {
        scenarioBindings
            .filter { $0.modelID == modelID && $0.identity == identity }
            .sorted {
                if $0.scenario != $1.scenario { return $0.scenario < $1.scenario }
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.createdAt < $1.createdAt
            }
    }

    private var availableScenarios: [AIScenario] {
        let existing = Set(bindings.map(\.scenario))
        return AIScenario.allCases.filter { existing.contains($0.rawValue) == false }
    }

    var body: some View {
        List {
            if bindings.isEmpty {
                Text(L10n.text("ai_settings.models.online.selection.none"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bindings) { binding in
                    Button {
                        presentedMode = .edit(binding.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AIScenario(rawValue: binding.scenario)?.localizedTitle ?? binding.scenario)
                            HStack(spacing: 8) {
                                if binding.isDefault {
                                    Text(L10n.text("ai_settings.scenario_default_hint"))
                                }
                                Text(String(format: "%.2f", binding.temperature))
                                Text("\(binding.maxTokens)")
                                if binding.isActive == false {
                                    Text("Inactive")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteBindings)
            }
        }
        .navigationTitle(L10n.text("ai_settings.models.online.field.scenarios"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedMode = .add
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(availableScenarios.isEmpty)
            }
        }
        .sheet(item: $presentedMode) { mode in
            CompatibleNavigationContainer {
                ModelScenarioBindingAddView(
                    mode: mode,
                    availableScenarios: availableScenarios,
                    makeBinding: makeBinding(for:),
                    existingBinding: existingBinding(for: mode),
                    smallTasks: smallTasks,
                    onCancel: { presentedMode = nil },
                    onSave: { binding in
                        saveBinding(binding, mode: mode)
                        presentedMode = nil
                    }
                )
            }
        }
    }

    private func makeBinding(for scenario: AIScenario) -> AIScenarioModelBinding {
        let bindingsInScenario = scenarioBindings.filter { $0.scenario == scenario.rawValue }
        return AIScenarioModelBinding(
            scenario: scenario.rawValue,
            identity: identity,
            modelID: modelID,
            temperature: scenario == .chat ? 0.6 : 0.2,
            maxTokens: 2048,
            position: (bindingsInScenario.map(\.position).max() ?? -1) + 1,
            isDefault: bindingsInScenario.contains(where: { $0.isDefault }) == false,
            isActive: true,
            systemProvision: defaultSystemProvision,
            briefDescription: defaultBriefDescription,
            aiToolScenarios: defaultToolScenarios,
            relatedTaskCodes: defaultRelatedTaskCodes
        )
    }

    private func existingBinding(for mode: ModelScenarioBindingEditorMode) -> AIScenarioModelBinding? {
        switch mode {
        case .add:
            return nil
        case .edit(let id):
            return scenarioBindings.first(where: { $0.id == id })
        }
    }

    private func saveBinding(_ binding: AIScenarioModelBinding, mode: ModelScenarioBindingEditorMode) {
        var binding = binding
        binding.updatedAt = Date()
        if binding.isDefault {
            for index in scenarioBindings.indices where scenarioBindings[index].scenario == binding.scenario {
                guard scenarioBindings[index].id != binding.id, scenarioBindings[index].isDefault else { continue }
                scenarioBindings[index].isDefault = false
                scenarioBindings[index].updatedAt = Date()
            }
        }

        switch mode {
        case .add:
            scenarioBindings.append(binding)
        case .edit(let id):
            guard let index = scenarioBindings.firstIndex(where: { $0.id == id }) else { return }
            scenarioBindings[index] = binding
        }

        onPersist?(ModelScenarioBindingPersistenceChange(upserted: binding))
    }

    private func deleteBindings(at offsets: IndexSet) {
        let ids = offsets.map { bindings[$0].id }
        scenarioBindings.removeAll { ids.contains($0.id) }
        for id in ids {
            onPersist?(ModelScenarioBindingPersistenceChange(deletedID: id))
        }
    }
}

private enum ModelScenarioBindingEditorMode: Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let id):
            return "edit-\(id.uuidString)"
        }
    }
}

private struct ModelScenarioBindingAddView: View {
    let mode: ModelScenarioBindingEditorMode
    let availableScenarios: [AIScenario]
    let makeBinding: (AIScenario) -> AIScenarioModelBinding
    let existingBinding: AIScenarioModelBinding?
    var smallTasks: [SmallTask]
    let onCancel: () -> Void
    let onSave: (AIScenarioModelBinding) -> Void

    @State private var selectedScenario: AIScenario
    @State private var draft: AIScenarioModelBinding

    init(
        mode: ModelScenarioBindingEditorMode,
        availableScenarios: [AIScenario],
        makeBinding: @escaping (AIScenario) -> AIScenarioModelBinding,
        existingBinding: AIScenarioModelBinding?,
        smallTasks: [SmallTask],
        onCancel: @escaping () -> Void,
        onSave: @escaping (AIScenarioModelBinding) -> Void
    ) {
        let initialBinding: AIScenarioModelBinding = {
            if let existingBinding {
                return existingBinding
            }
            let initialScenario = availableScenarios.first ?? .chat
            return makeBinding(initialScenario)
        }()
        self.mode = mode
        self.availableScenarios = availableScenarios
        self.makeBinding = makeBinding
        self.existingBinding = existingBinding
        self.smallTasks = smallTasks
        self.onCancel = onCancel
        self.onSave = onSave
        _selectedScenario = State(initialValue: AIScenario(rawValue: initialBinding.scenario) ?? .chat)
        _draft = State(initialValue: initialBinding)
    }

    var body: some View {
        ModelScenarioBindingForm(
            binding: $draft,
            smallTasks: smallTasks,
            scenarioPicker: scenarioPicker
        )
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel")) { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { onSave(draft) }
                    .disabled(isSaveDisabled)
            }
        }
        .onChange(of: selectedScenario, perform: { newScenario in
            guard case .add = mode else { return }
            let previousID = draft.id
            draft = makeBinding(newScenario)
            draft.id = previousID
        })
    }

    private var scenarioPicker: AnyView {
        guard case .add = mode else { return AnyView(EmptyView()) }
        return AnyView(
            Picker(L10n.text("ai_settings.models.online.field.scenarios"), selection: $selectedScenario) {
                ForEach(availableScenarios, id: \.rawValue) { scenario in
                    Text(scenario.localizedTitle).tag(scenario)
                }
            }
        )
    }

    private var title: String {
        switch mode {
        case .add:
            return L10n.text("common.add")
        case .edit:
            return AIScenario(rawValue: draft.scenario)?.localizedTitle ?? draft.scenario
        }
    }

    private var confirmTitle: String {
        switch mode {
        case .add:
            return L10n.text("common.add")
        case .edit:
            return L10n.text("common.done")
        }
    }

    private var isSaveDisabled: Bool {
        switch mode {
        case .add:
            return availableScenarios.isEmpty
        case .edit:
            return false
        }
    }
}

private struct ModelScenarioBindingForm: View {
    @Binding var binding: AIScenarioModelBinding
    var smallTasks: [SmallTask]
    var scenarioPicker: AnyView = AnyView(EmptyView())

    var body: some View {
        Form {
            Section {
                scenarioPicker
                Toggle("Active", isOn: $binding.isActive)
                Toggle(L10n.text("ai_settings.scenario_default_hint"), isOn: $binding.isDefault)
            }

            Section {
                Stepper(
                    "\(L10n.text("ai_settings.temperature")) \(String(format: "%.2f", binding.temperature))",
                    value: $binding.temperature,
                    in: 0...2,
                    step: 0.05
                )
                Stepper(
                    "\(L10n.text("ai_settings.max_tokens")) \(binding.maxTokens)",
                    value: $binding.maxTokens,
                    in: 256...32768,
                    step: 256
                )
            }

            Section {
                TextField("System", text: $binding.systemProvision)
                TextField(L10n.text("common.description"), text: $binding.briefDescription)
            }

            Section(L10n.text("common.tools")) {
                NavigationLink {
                    GroupedToolSelectionView(
                        title: L10n.text("common.tools"),
                        selectedValues: toolSelection
                    )
                } label: {
                    HStack {
                        Text(L10n.text("common.tools"))
                        Spacer()
                        Text(toolSelectionSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if smallTasks.isEmpty == false {
                Section(L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "Related small tasks row title")) {
                    NavigationLink {
                        MultiSelectOptionsView(
                            title: L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "Related small tasks selector title"),
                            options: smallTasks.map { ($0.code, "\($0.name)（\($0.code)）") },
                            selectedValues: relatedTaskSelection
                        )
                    } label: {
                        HStack {
                            Text(L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "Related small tasks row title"))
                            Spacer()
                            Text("\(binding.relatedTaskCodes.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var toolSelection: Binding<Set<String>> {
        Binding(
            get: { SparkToolName.selectedSet(fromStoredToolNames: binding.aiToolScenarios) },
            set: { binding.aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: $0) }
        )
    }

    private var relatedTaskSelection: Binding<Set<String>> {
        Binding(
            get: { Set(binding.relatedTaskCodes) },
            set: { binding.relatedTaskCodes = $0.sorted() }
        )
    }

    private var toolSelectionSummary: String {
        let selected = SparkToolName.selectedSet(fromStoredToolNames: binding.aiToolScenarios)
        let total = SparkToolName.all.count
        if selected.count == total {
            return L10n.text("common.all")
        }
        return "\(selected.count)/\(total)"
    }
}
