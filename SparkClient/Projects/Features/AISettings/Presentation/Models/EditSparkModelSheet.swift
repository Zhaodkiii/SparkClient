import SwiftUI

/// 对齐 Health `EditModelSheetView` 子集：显示名、SF 图标、非 LOCAL 且非系统时的能力开关。
struct EditSparkModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let modelID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var iconSymbol = "circle.dotted.circle"
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var showIconPicker = false

    private let iconCandidates = [
        "circle.dotted.circle", "cpu", "sparkles", "brain.head.profile",
        "heart.text.square", "stethoscope", "leaf", "bolt.heart"
    ]

    private var model: AllModels? {
        viewModel.snapshot.allModels.first(where: { $0.id == modelID })
    }

    private var canEditCapabilities: Bool {
        guard let m = model else { return false }
        return m.source != .system && m.company.uppercased() != LocalModelService.localCompany.uppercased()
    }

    var body: some View {
        NavigationView {
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
                NavigationView {
                    List {
                        ForEach(iconCandidates, id: \.self) { icon in
                            Button {
                                iconSymbol = icon
                                showIconPicker = false
                            } label: {
                                HStack {
                                    Image(systemName: icon)
                                    Text(icon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle(L10n.text("ai_settings.models.edit.icon_picker_title"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.cancel")) { showIconPicker = false }
                        }
                    }
                }
            }
            .onAppear {
                syncFromModel()
            }
        }
    }

    private func syncFromModel() {
        guard let m = model else { return }
        displayName = m.displayName
        iconSymbol = m.iconSymbol ?? "circle.dotted.circle"
        supportsText = m.supportsText
        supportsMultimodal = m.supportsMultimodal
        supportsReasoning = m.supportsReasoning
        reasoningControllable = m.reasoningControllable
        supportsToolUse = m.supportsToolUse
        supportsImageGen = m.supportsImageGen
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
        }
        viewModel.replaceModel(m)
        dismiss()
    }
}
