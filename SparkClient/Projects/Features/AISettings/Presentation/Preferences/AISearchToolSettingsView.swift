import SwiftUI

struct AISearchToolSettingsView: View {
    @Binding var userInfo: UserInfo
    @Binding var searchKeys: [SearchKeys]
    @Binding var toolKeys: [ToolKeys]

    var body: some View {
        List {
            Section(L10n.text("ai_settings.section.search_knowledge")) {
                Toggle(L10n.text("ai_settings.field.use_search"), isOn: $userInfo.useSearch)
                Toggle(L10n.text("ai_settings.field.bilingual_search"), isOn: $userInfo.bilingualSearch)
                Stepper(value: $userInfo.searchCount, in: 1...50) {
                    HStack {
                        Text(L10n.text("ai_settings.field.search_count"))
                        Spacer()
                        Text("\(userInfo.searchCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(L10n.text("ai_settings.field.use_knowledge"), isOn: $userInfo.useKnowledge)
                Stepper(value: $userInfo.knowledgeCount, in: 1...50) {
                    HStack {
                        Text(L10n.text("ai_settings.field.knowledge_count"))
                        Spacer()
                        Text("\(userInfo.knowledgeCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Slider(value: $userInfo.knowledgeSimilarity, in: 0.1...1.0, step: 0.05)
                Text("\(L10n.text("ai_settings.field.knowledge_similarity")): \(String(format: "%.2f", userInfo.knowledgeSimilarity))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("ai_settings.section.search_keys")) {
                ForEach($searchKeys) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.text("ai_settings.field.name"), text: $item.name)
                        TextField(L10n.text("ai_settings.field.company"), text: $item.company)
                        TextField(L10n.text("ai_settings.endpoint"), text: $item.requestURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Toggle(L10n.text("ai_settings.field.enabled"), isOn: $item.isUsing)
                    }
                }
                .onDelete { searchKeys.remove(atOffsets: $0) }
                Button(L10n.text("ai_settings.action.add_search_key")) {
                    searchKeys.append(
                        SearchKeys(
                            name: "",
                            company: "",
                            key: "",
                            requestURL: "",
                            isUsing: false,
                            searchClass: "web",
                            help: "",
                            source: .custom,
                            timestamp: Date()
                        )
                    )
                }
            }

            Section(L10n.text("ai_settings.section.tool_keys")) {
                ForEach($toolKeys) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.text("ai_settings.field.name"), text: $item.name)
                        TextField(L10n.text("ai_settings.field.company"), text: $item.company)
                        TextField(L10n.text("ai_settings.endpoint"), text: $item.requestURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Toggle(L10n.text("ai_settings.field.enabled"), isOn: $item.isUsing)
                    }
                }
                .onDelete { toolKeys.remove(atOffsets: $0) }
                Button(L10n.text("ai_settings.action.add_tool_key")) {
                    toolKeys.append(
                        ToolKeys(
                            name: "",
                            company: "",
                            key: "",
                            requestURL: "",
                            isUsing: false,
                            toolClass: "tool",
                            help: "",
                            source: .custom,
                            timestamp: Date()
                        )
                    )
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.search_tools"))
    }
}
