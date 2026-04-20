import SwiftUI

/// 新建或编辑本地智能体（对齐 Health `AddAgentView` 的基础字段）。
struct ModelsSettingsAgentSheet: View {
    let localBaseModels: [AllModels]
    var editingAgent: AllModels?
    let onCreate: (String, String, String, String) -> Void
    let onUpdate: ((UUID, String, String, String, String) -> Void)?

    @State private var displayName = ""
    @State private var iconSymbol = "stethoscope"
    @State private var selectedBaseModelName = ""
    @State private var systemPrompt = ""
    @State private var showIconPicker = false
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { editingAgent != nil }

    var body: some View {
        List {
            Section(L10n.text("ai_settings.models.agent.section.basic")) {
                TextField(L10n.text("ai_settings.models.agent.field.name"), text: $displayName)
                Picker(L10n.text("ai_settings.models.agent.field.base_model"), selection: $selectedBaseModelName) {
                    ForEach(localBaseModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                if let selectedModel = localBaseModels.first(where: { $0.name == selectedBaseModelName }) {
                    AgentBaseModelPreview(model: selectedModel)
                }
            }

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

            Section(L10n.text("ai_settings.models.agent.section.system_prompt")) {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 96)
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
                        onUpdate?(agent.id, displayName, iconSymbol, selectedBaseModelName, systemPrompt)
                    } else {
                        onCreate(displayName, iconSymbol, selectedBaseModelName, systemPrompt)
                    }
                    dismiss()
                }
                .disabled(canSave == false)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ModelIconPickerSheet(selectedIcon: $iconSymbol)
        }
        .onAppear {
            if let agent = editingAgent {
                displayName = agent.displayName
                iconSymbol = agent.iconSymbol ?? "stethoscope"
                selectedBaseModelName = agent.baseModelName ?? ""
                systemPrompt = agent.systemPrompt ?? ""
            } else if selectedBaseModelName.isEmpty, let first = localBaseModels.first {
                selectedBaseModelName = first.name
            }
        }
    }

    private var canSave: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedBaseModelName.isEmpty == false
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
