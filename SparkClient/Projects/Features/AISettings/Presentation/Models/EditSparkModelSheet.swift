import SwiftUI

/// 对齐 Health `EditModelSheetView` 子集：显示名、SF 图标、非 LOCAL 且非系统时的能力开关。
struct EditSparkModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let modelID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var iconSymbol = ModelIconCatalog.fallbackSymbol
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var selectedScenarioRawValues: Set<String> = []
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var selectedTaskCodes: Set<String> = []
    @State private var showIconPicker = false
    @State private var hasSyncedFromModel = false

    private var model: AllModels? {
        viewModel.snapshot.allModels.first(where: { $0.id == modelID })
    }

    private var canEditCapabilities: Bool {
        guard let m = model else { return false }
        return AIProviderAdapterRegistry.adapter(for: m.providerID).isLocal == false
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                Section(L10n.text("ai_settings.models.edit.section.name")) {
                    TextField(L10n.text("ai_settings.models.edit.field.display_name"), text: $displayName)
                }
                Section(L10n.text("ai_settings.models.edit.section.icon")) {
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
                if canEditCapabilities {
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

                        NavigationLink {
                            MultiSelectOptionsView(
                                title: "关联小任务",
                                options: viewModel.snapshot.smallTasks.map { ($0.code, "\($0.name)（\($0.code)）") },
                                selectedValues: $selectedTaskCodes
                            )
                        } label: {
                            HStack {
                                Text("关联小任务")
                                Spacer()
                                Text("\(selectedTaskCodes.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section(L10n.text("ai_settings.models.edit.section.capabilities")) {
                        Toggle(L10n.text("ai_settings.models.online.toggle.supports_text"), isOn: $supportsText)
                        Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: $supportsMultimodal)
                        Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: $supportsReasoning)
                        Toggle(L10n.text("ai_settings.field.reasoning_controllable"), isOn: $reasoningControllable)
                        Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: $supportsToolUse)
                        Toggle(L10n.text("ai_settings.models.online.toggle.image_gen"), isOn: $supportsImageGen)
                    }
                }
            }
            .navigationTitle(L10n.text("ai_settings.models.edit.nav_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.save")) { save() }
                }
            }
            .sheet(isPresented: $showIconPicker) {
                ModelIconPickerSheet(selectedIcon: $iconSymbol)
            }
            .onAppear {
                guard hasSyncedFromModel == false else { return }
                syncFromModel()
                hasSyncedFromModel = true
            }
        }
    }

    private func syncFromModel() {
        guard let m = model else { return }
        displayName = m.displayName
        iconSymbol = m.iconSymbol ?? ModelIconCatalog.fallbackSymbol
        supportsText = m.supportsText
        supportsMultimodal = m.supportsMultimodal
        supportsReasoning = m.supportsReasoning
        reasoningControllable = m.reasoningControllable
        supportsToolUse = m.supportsToolUse
        supportsImageGen = m.supportsImageGen
        selectedScenarioRawValues = Set(m.aiScenarios)
        selectedToolNames = m.selectedToolNames
        selectedTaskCodes = Set(m.relatedTaskCodes)
    }

    private func save() {
        guard var m = viewModel.snapshot.allModels.first(where: { $0.id == modelID }) else {
            dismiss()
            return
        }
        m.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        m.iconSymbol = iconSymbol
        if canEditCapabilities {
            m.supportsText = supportsText
            m.supportsMultimodal = supportsMultimodal
            m.supportsReasoning = supportsReasoning
            m.reasoningControllable = reasoningControllable
            m.supportsToolUse = supportsToolUse
            m.supportsImageGen = supportsImageGen
            m.aiScenarios = selectedScenarioRawValues.sorted()
            m.aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: selectedToolNames)
            m.relatedTaskCodes = selectedTaskCodes.sorted()
        }
        Task {
            let didSave = await viewModel.replaceModelAndPersist(m)
            if didSave {
                await MainActor.run { dismiss() }
            }
        }
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
