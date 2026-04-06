import SwiftUI

/// 对齐 Health `AddOnlineModelView`：表单添加云端模型（无 SwiftData）。
struct AddOnlineModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var displayName = ""
    @State private var priceTier = 0
    @State private var isHidden = false
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var selectedCompany = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var apiKeyRows: [APIKeys] {
        viewModel.snapshot.apiKeys.filter {
            !$0.isHidden &&
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != LocalModelService.localCompany.uppercased()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(L10n.text("ai_settings.models.online.section.basic")) {
                    TextField(L10n.text("ai_settings.models.online.field.api_name"), text: $name)
                    TextField(L10n.text("ai_settings.models.online.field.display_name"), text: $displayName)
                    Picker(L10n.text("ai_settings.models.online.field.vendor"), selection: $selectedCompany) {
                        ForEach(apiKeyRows, id: \.id) { key in
                            Text(key.name.isEmpty ? key.company : key.name)
                                .tag(key.company)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(L10n.text("ai_settings.models.online.section.price")) {
                    Picker(L10n.text("ai_settings.field.price_tier"), selection: $priceTier) {
                        Text(L10n.text("ai_settings.field.price_tier.free")).tag(0)
                        Text(L10n.text("ai_settings.field.price_tier.economy")).tag(1)
                        Text(L10n.text("ai_settings.field.price_tier.standard")).tag(2)
                        Text(L10n.text("ai_settings.field.price_tier.premium")).tag(3)
                    }
                    .pickerStyle(.menu)
                }
                Section(L10n.text("ai_settings.models.online.section.capabilities")) {
                    Toggle(L10n.text("ai_settings.models.online.toggle.default_hidden"), isOn: $isHidden)
                    Toggle(L10n.text("ai_settings.models.online.toggle.supports_text"), isOn: $supportsText)
                    Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: $supportsMultimodal)
                    Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: $supportsReasoning)
                    Toggle(L10n.text("ai_settings.field.reasoning_controllable"), isOn: $reasoningControllable)
                    Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: $supportsToolUse)
                    Toggle(L10n.text("ai_settings.models.online.toggle.image_gen"), isOn: $supportsImageGen)
                }
            }
            .navigationTitle(L10n.text("ai_settings.models.online.nav_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.models.online.save")) { save() }
                }
            }
            .alert(L10n.text("ai_settings.models.online.error_title"), isPresented: $showAlert) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if selectedCompany.isEmpty, let first = apiKeyRows.first {
                    selectedCompany = first.company
                }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = selectedCompany.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.api_name")
            showAlert = true
            return
        }
        guard !d.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.display_name")
            showAlert = true
            return
        }
        guard !c.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.vendor")
            showAlert = true
            return
        }
        viewModel.appendOnlineModel(
            name: n,
            displayName: d,
            company: c,
            priceTier: priceTier,
            isHidden: isHidden,
            supportsText: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            reasoningControllable: reasoningControllable,
            supportsToolUse: supportsToolUse,
            supportsImageGen: supportsImageGen
        )
        dismiss()
    }
}
