import SwiftUI

/// 新建或编辑智能体（对齐 Health `AddAgentView` 的基础字段）。
struct ModelsSettingsAgentSheet: View {
    let baseModels: [AllModels]
    var editingAgent: AllModels?
    var promptTooling: AISettingsPromptTooling = .unavailable
    let onCreate: (String, String, String, String, [String], [String]) -> Void
    let onUpdate: ((UUID, String, String, String, String, [String], [String]) -> Void)?

    @State private var displayName = ""
    @State private var iconSymbol = "stethoscope"
    @State private var selectedBaseModelName = ""
    @State private var systemPrompt = ""
    @State private var selectedScenarioRawValues: Set<String> = []
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var showIconPicker = false
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false
    @State private var autoFillInProgress = false
    @State private var autoFilled = false
    @State private var autoFillOriginalText = ""
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var hasSyncedFromModel = false

    private var isEditing: Bool { editingAgent != nil }

    var body: some View {
        List {
            Section(L10n.text("ai_settings.models.agent.section.icons")) {
                HStack {
                    Spacer()
                    Button {
                        showIconPicker = true
                    } label: {
                        Image(systemName: iconSymbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section(L10n.text("ai_settings.models.agent.section.basic")) {
                TextField(L10n.text("ai_settings.models.agent.field.name"), text: $displayName)
            }

            Section(L10n.text("ai_settings.models.agent.section.system_prompt")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $systemPrompt)
                        .scrollContentBackgroundIfAvailable(.hidden)
                        .frame(minHeight: 150)

                    HStack(spacing: 10) {
                        autoFillButton

                        Spacer()
                        Text(L10n.text("prompt_input.tools"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            showVoiceInput = true
                        } label: {
                            Image(systemName: "microphone.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("prompt_input.voice.title"))

                        Button {
                            showTextInputDrawer = true
                        } label: {
                            Image(systemName: "chevron.up.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("prompt_input.drawer.title"))
                    }
                    .foregroundStyle(.tint)
                }
            }

            Section(L10n.text("ai_settings.models.agent.section.base_model")) {
                Picker(L10n.text("ai_settings.models.agent.field.base_model"), selection: $selectedBaseModelName) {
                    ForEach(baseModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                if let selectedModel = baseModels.first(where: { $0.name == selectedBaseModelName }) {
                    AgentBaseModelPreview(model: selectedModel)
                } else if baseModels.isEmpty {
                    Text(L10n.text("ai_settings.models.agent.empty.base_models"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text("ai_settings.models.online.section.usage")) {
                NavigationLink {
                    MultiSelectOptionsView(
                        title: L10n.text("ai_settings.models.online.field.scenarios"),
                        options: AIScenario.allCases.map { ($0.rawValue, $0.localizedTitle) },
                        selectedValues: $selectedScenarioRawValues
                    )
                } label: {
                    HStack {
                        Text(L10n.text("ai_settings.models.online.field.scenarios"))
                        Spacer()
                        Text(selectedScenarioSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    GroupedToolSelectionView(
                        title: L10n.text("ai_settings.models.online.field.tools"),
                        selectedValues: $selectedToolNames
                    )
                } label: {
                    HStack {
                        Text(L10n.text("ai_settings.models.online.field.tools"))
                        Spacer()
                        Text(selectedToolsSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? L10n.text("ai_settings.models.agent.nav.edit_title") : L10n.text("ai_settings.models.agent.nav.new_title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? L10n.text("ai_settings.save") : L10n.text("ai_settings.models.agent.action.create")) {
                    if isEditing, let agent = editingAgent {
                        onUpdate?(
                            agent.id,
                            displayName,
                            iconSymbol,
                            selectedBaseModelName,
                            systemPrompt,
                            selectedScenarioRawValues.sorted(),
                            SparkToolName.storageValues(forSelectedToolNames: selectedToolNames)
                        )
                    } else {
                        onCreate(
                            displayName,
                            iconSymbol,
                            selectedBaseModelName,
                            systemPrompt,
                            selectedScenarioRawValues.sorted(),
                            SparkToolName.storageValues(forSelectedToolNames: selectedToolNames)
                        )
                    }
                    dismiss()
                }
                .disabled(canSave == false)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ModelIconPickerSheet(selectedIcon: $iconSymbol)
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $systemPrompt,
                isPresented: $showTextInputDrawer,
                onAutoFill: {
                    try await promptTooling.autoFillAgentPrompt(displayName, selectedBaseModelName)
                },
                onTranslate: {
                    try await promptTooling.translate(systemPrompt)
                },
                onOCRImage: { image in
                    try await promptTooling.ocrImage(image)
                }
            )
                .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $systemPrompt,
                isPresented: $showVoiceInput,
                onPolish: {
                    try await promptTooling.autoFillAgentPrompt(displayName, selectedBaseModelName)
                }
            )
                .sparkInputPresentationChromeIfAvailable()
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { actionError != nil },
            set: { if $0 == false { actionError = nil } }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(actionError ?? "")
        }
        .onAppear {
            guard hasSyncedFromModel == false else { return }

            if let agent = editingAgent {
                displayName = agent.displayName
                iconSymbol = agent.iconSymbol ?? "stethoscope"
                selectedBaseModelName = agent.baseModelName ?? ""
                systemPrompt = agent.systemPrompt ?? ""
                selectedScenarioRawValues = Set(agent.aiScenarios)
                selectedToolNames = agent.selectedToolNames
            } else if selectedBaseModelName.isEmpty, let first = baseModels.first {
                selectedBaseModelName = first.name
            }
            hasSyncedFromModel = true
        }
    }

    private var autoFillButton: some View {
        Button {
            runAutoFill()
        } label: {
            HStack(spacing: 5) {
                if autoFillInProgress {
                    ProgressView()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofilling"))
                        .font(.caption)
                } else if autoFilled {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.undo_autofill"))
                        .font(.caption)
                } else {
                    Image(systemName: "pencil.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofill"))
                        .font(.caption)
                }
            }
            .foregroundStyle(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.systemGray) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(autoFillInProgress || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func runAutoFill() {
        if autoFilled {
            systemPrompt = autoFillOriginalText
            autoFilled = false
            autoFillOriginalText = ""
            return
        }
        autoFillOriginalText = systemPrompt
        autoFillInProgress = true
        Task {
            do {
                let raw = try await promptTooling.autoFillAgentPrompt(displayName, selectedBaseModelName)
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty == false {
                    systemPrompt = result
                    autoFilled = true
                }
            } catch {
                actionError = error.localizedDescription
            }
            autoFillInProgress = false
        }
    }

    private var canSave: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedBaseModelName.isEmpty == false &&
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var selectedScenarioSummary: String {
        if selectedScenarioRawValues.isEmpty {
            return L10n.text("ai_settings.models.online.selection.none")
        }
        return "\(selectedScenarioRawValues.count)"
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("ai_settings.models.online.selection.all")
        }
        return "\(selectedToolNames.count)/\(total)"
    }
}

/// 与 `ModelsSettingsView` 内原 `BaseModelCard` 一致，供智能体 Sheet 预览基座模型。
private struct AgentBaseModelPreview: View {
    let model: AllModels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName)
                .font(.headline)
            Text(model.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                capabilityChip(model.isLocalModel ? L10n.text("ai_settings.models.badge.local") : L10n.text("ai_settings.models.badge.service"), enabled: true)
                capabilityChip(L10n.text("ai_settings.models.capability.reasoning"), enabled: model.supportsReasoning)
                capabilityChip(L10n.text("ai_settings.models.capability.tools"), enabled: model.supportsToolUse)
                capabilityChip(L10n.text("ai_settings.models.capability.multimodal"), enabled: model.supportsMultimodal)
            }
        }
        .padding(.vertical, 4)
    }

    private func capabilityChip(_ title: String, enabled: Bool) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(enabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
            .clipShape(Capsule())
    }
}
