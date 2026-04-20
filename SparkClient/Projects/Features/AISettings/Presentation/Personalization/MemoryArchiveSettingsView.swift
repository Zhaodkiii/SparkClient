import SwiftUI

struct MemoryArchiveSettingsView: View {
    @Binding var memoryArchive: [MemoryArchive]

    var body: some View {
        List {
            ForEach($memoryArchive) { $item in
                Section(item.title.isEmpty ? L10n.text("ai_settings.memory_item") : item.title) {
                    TextField(L10n.text("ai_settings.field.title"), text: $item.title)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("ai_settings.field.content"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $item.content)
                            .frame(minHeight: 88, maxHeight: 176)
                    }
                    Toggle(L10n.text("ai_settings.field.pinned"), isOn: $item.pinned)
                }
            }
            .onDelete { memoryArchive.remove(atOffsets: $0) }

            Button(L10n.text("ai_settings.action.add_memory")) {
                memoryArchive.append(
                    MemoryArchive(
                        title: "",
                        content: "",
                        pinned: false,
                        timestamp: Date()
                    )
                )
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.memory_archive"))
    }
}
