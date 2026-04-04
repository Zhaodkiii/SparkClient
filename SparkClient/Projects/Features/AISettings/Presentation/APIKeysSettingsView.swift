import SwiftUI

struct APIKeysSettingsView: View {
    @Binding var apiKeys: [APIKeys]

    var body: some View {
        List {
            ForEach($apiKeys) { $item in
                Section(item.name.isEmpty ? L10n.text("ai_settings.api_key_item") : item.name) {
                    TextField(L10n.text("ai_settings.field.name"), text: $item.name)
                    TextField(L10n.text("ai_settings.field.company"), text: $item.company)
                    TextField(L10n.text("ai_settings.endpoint"), text: $item.requestURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.text("ai_settings.api_key"), text: $item.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle(L10n.text("ai_settings.field.enabled"), isOn: Binding(
                        get: { item.isHidden == false },
                        set: { item.isHidden = !$0 }
                    ))
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(L10n.text("ai_settings.row.api_keys"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAPIKey()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func addAPIKey() {
        apiKeys.append(
            APIKeys(
                name: "",
                company: "",
                key: "",
                requestURL: "",
                isHidden: true,
                help: "",
                source: .custom,
                timestamp: Date()
            )
        )
    }

    private func delete(at offsets: IndexSet) {
        apiKeys.remove(atOffsets: offsets)
    }
}
