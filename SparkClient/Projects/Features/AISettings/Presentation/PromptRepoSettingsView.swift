import SwiftUI

struct PromptRepoSettingsView: View {
    @Binding var promptRepo: [PromptRepo]

    var body: some View {
        List {
            ForEach($promptRepo) { $item in
                Section(item.title.isEmpty ? L10n.text("ai_settings.prompt_item") : item.title) {
                    TextField(L10n.text("ai_settings.field.title"), text: $item.title)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("ai_settings.field.content"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $item.content)
                            .frame(minHeight: 88, maxHeight: 176)
                    }
                    Toggle(L10n.text("ai_settings.field.system_preset"), isOn: $item.isSystem)
                }
            }
            .onDelete { promptRepo.remove(atOffsets: $0) }

            Button(L10n.text("ai_settings.action.add_prompt")) {
                promptRepo.append(
                    PromptRepo(
                        title: "",
                        content: "",
                        isSystem: false,
                        timestamp: Date()
                    )
                )
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.prompt_repo"))
    }
}
