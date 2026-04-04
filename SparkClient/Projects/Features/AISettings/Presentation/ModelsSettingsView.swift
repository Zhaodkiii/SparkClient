import SwiftUI

struct ModelsSettingsView: View {
    @Binding var models: [AllModels]

    var body: some View {
        List {
            ForEach($models) { $model in
                Section(model.displayName.isEmpty ? L10n.text("ai_settings.model_item") : model.displayName) {
                    TextField(L10n.text("ai_settings.field.display_name"), text: $model.displayName)
                    TextField(L10n.text("ai_settings.model"), text: $model.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(L10n.text("ai_settings.field.company"), text: $model.company)
                    Picker(L10n.text("ai_settings.field.identity"), selection: $model.identity) {
                        ForEach(AIModelIdentity.allCases, id: \.self) { identity in
                            Text(identity.rawValue).tag(identity)
                        }
                    }
                    Toggle(L10n.text("ai_settings.field.visible"), isOn: Binding(
                        get: { model.isHidden == false },
                        set: { model.isHidden = !$0 }
                    ))
                    Toggle(L10n.text("ai_settings.field.supports_search"), isOn: $model.supportsSearch)
                    Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: $model.supportsMultimodal)
                    Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: $model.supportsReasoning)
                    Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: $model.supportsToolUse)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(L10n.text("ai_settings.row.models"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addModel()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func addModel() {
        models.append(
            AllModels(
                name: "",
                displayName: "",
                identity: .model,
                position: (models.map(\.position).max() ?? 0) + 1,
                company: "",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .custom,
                timestamp: Date()
            )
        )
    }

    private func delete(at offsets: IndexSet) {
        models.remove(atOffsets: offsets)
    }
}
