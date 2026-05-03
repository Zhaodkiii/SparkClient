import SwiftUI
#if canImport(UIKit)
import SafariServices
import UIKit
#endif

private struct SearchKeyEditorContext: Identifiable {
    let id: UUID
    var key: SearchKeys
    var isNew: Bool

    init(key: SearchKeys, isNew: Bool) {
        self.id = key.id
        self.key = key
        self.isNew = isNew
    }
}

private struct SearchHelpPage: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct AISearchToolSettingsView: View {
    @Binding var preferences: AISearchToolPreferences
    @Binding var searchKeys: [SearchKeys]
    @Binding var toolKeys: [ToolKeys]

    @State private var editorContext: SearchKeyEditorContext?
    @State private var errorMessage: String?

    private var sortedSearchKeys: [SearchKeys] {
        searchKeys.sorted {
            let lhs = displayName(for: $0)
            let rhs = displayName(for: $1)
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.top, 4)

                    Text(L10n.text("ai_settings.search.intro"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section(L10n.text("ai_settings.search.section.active_search")) {
                Toggle(L10n.text("ai_settings.field.use_search"), isOn: $preferences.useSearch)
                    .tint(.blue)
            }

            Section(L10n.text("ai_settings.search.section.result_count")) {
                Stepper(value: $preferences.searchCount, in: 5...20) {
                    HStack {
                        Text(L10n.text("ai_settings.field.search_count"))
                        Spacer()
                        Text("\(preferences.searchCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.text("ai_settings.search.section.bilingual")) {
                Toggle(L10n.text("ai_settings.field.bilingual_search"), isOn: $preferences.bilingualSearch)
                    .tint(.blue)
            }

            Section(L10n.text("ai_settings.search.section.providers")) {
                ForEach(sortedSearchKeys) { key in
                    searchEngineRow(for: key)
                }
                .onDelete(perform: deleteSearchKeys)
            }

            Section(L10n.text("ai_settings.search.section.capabilities")) {
                Label(L10n.text("ai_settings.search.capability.web_search"), systemImage: "network")
                Label(L10n.text("ai_settings.search.capability.paper_search"), systemImage: "graduationcap")
                Label(L10n.text("ai_settings.search.capability.web_page_read"), systemImage: "text.and.command.macwindow")
                Label(L10n.text("ai_settings.search.capability.remote_file_read"), systemImage: "text.document")
            }
        }
        .navigationTitle(L10n.text("ai_settings.search.nav_title"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    editorContext = SearchKeyEditorContext(key: makeBlankSearchKey(), isNew: true)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $editorContext) { context in
            SearchKeyEditorView(
                initialKey: context.key,
                isNew: context.isNew,
                onSave: { key in
                    saveSearchKey(key, isNew: context.isNew)
                }
            )
        }
        .alert(L10n.text("common.notice"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { presented in
                if presented == false { errorMessage = nil }
            }
        )) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func searchEngineRow(for key: SearchKeys) -> some View {
        HStack(spacing: 12) {
            Button {
                editorContext = SearchKeyEditorContext(key: key, isNew: false)
            } label: {
                HStack(spacing: 12) {
                    Image(companyIconName(for: key.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(displayName(for: key))
                                .foregroundStyle(.primary)
                            if key.source == .custom {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(key.company.uppercased())
                            Text(priceHint(for: key.company))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: hasAPIKey(key) ? "key.fill" : "key")
                        .foregroundStyle(hasAPIKey(key) ? .blue : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { key.isUsing },
                set: { enabled in
                    setActiveSearchProvider(id: key.id, enabled: enabled)
                }
            ))
            .labelsHidden()
            .tint(.blue)
        }
    }

    private func saveSearchKey(_ key: SearchKeys, isNew: Bool) {
        var next = key
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.company = next.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        next.key = next.key.trimmingCharacters(in: .whitespacesAndNewlines)
        next.requestURL = next.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        next.searchClass = next.searchClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "web" : next.searchClass
        next.timestamp = Date()
        next.revision += 1

        if next.isUsing {
            for index in searchKeys.indices {
                searchKeys[index].isUsing = false
            }
        }

        if isNew {
            searchKeys.append(next)
        } else if let index = searchKeys.firstIndex(where: { $0.id == next.id }) {
            searchKeys[index] = next
        }

        impact(.medium)
    }

    private func setActiveSearchProvider(id: UUID, enabled: Bool) {
        guard let selected = searchKeys.first(where: { $0.id == id }) else { return }
        if enabled, SearchProviderID(company: selected.company) != .spark, hasAPIKey(selected) == false {
            errorMessage = String(format: L10n.text("ai_settings.search.error.need_api_key_format"), displayName(for: selected))
            return
        }

        for index in searchKeys.indices {
            if searchKeys[index].id == id {
                searchKeys[index].isUsing = enabled
                searchKeys[index].timestamp = Date()
                searchKeys[index].revision += 1
            } else if enabled {
                searchKeys[index].isUsing = false
            }
        }
        impact(.light)
    }

    private func deleteSearchKeys(at offsets: IndexSet) {
        let ids = offsets.map { sortedSearchKeys[$0].id }
        searchKeys.removeAll { ids.contains($0.id) }
    }

    private func makeBlankSearchKey() -> SearchKeys {
        SearchKeys(
            name: "",
            company: "",
            key: "",
            requestURL: "",
            isUsing: false,
            searchClass: "web",
            help: "",
            source: .custom,
            timestamp: Date(),
            priority: 0,
            revision: 1
        )
    }

    private func displayName(for key: SearchKeys) -> String {
        let name = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        let company = key.company.trimmingCharacters(in: .whitespacesAndNewlines)
        return company.isEmpty ? L10n.text("ai_settings.search.provider.untitled") : company
    }

    private func hasAPIKey(_ key: SearchKeys) -> Bool {
        key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func priceHint(for company: String) -> String {
        switch company.uppercased() {
        case "GOOGLE_SEARCH":
            return L10n.text("ai_settings.search.price.google")
        case "TAVILY":
            return L10n.text("ai_settings.search.price.tavily")
        case "LANGSEARCH":
            return L10n.text("ai_settings.search.price.free")
        case "BRAVE":
            return L10n.text("ai_settings.search.price.brave")
        case "SPARK":
            return L10n.text("ai_settings.search.price.spark")
        default:
            return L10n.text("ai_settings.search.price.provider")
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private struct SearchKeyEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key: SearchKeys
    @State private var testResult: Bool?
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var helpPage: SearchHelpPage?

    let isNew: Bool
    let onSave: (SearchKeys) -> Void

    init(initialKey: SearchKeys, isNew: Bool, onSave: @escaping (SearchKeys) -> Void) {
        _key = State(initialValue: initialKey)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        Image(companyIconName(for: key.company))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .padding(.top, 4)

                        Text(String(format: L10n.text("ai_settings.search.editor.intro_format"), displayName))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let url = URL(string: key.help), key.help.isEmpty == false {
                            Button {
                                helpPage = SearchHelpPage(
                                    url: url,
                                    title: String(format: L10n.text("ai_settings.search.editor.help_title_format"), displayName)
                                )
                            } label: {
                                Label(
                                    String(format: L10n.text("ai_settings.search.editor.help_link_format"), displayName),
                                    systemImage: "safari"
                                )
                                .font(.footnote)
                            }
                        } else {
                            Text(L10n.text("ai_settings.search.editor.help_fallback"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section(L10n.text("ai_settings.search.editor.section.basic")) {
                    TextField(L10n.text("ai_settings.field.name"), text: $key.name)
                    TextField(L10n.text("ai_settings.field.company"), text: $key.company)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField(L10n.text("ai_settings.endpoint"), text: $key.requestURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L10n.text("ai_settings.search.editor.field.help_link"), text: $key.help)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section(L10n.text("ai_settings.search.editor.section.key")) {
                    SecureField(L10n.text("ai_settings.search.editor.field.key_placeholder"), text: $key.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(L10n.text("ai_settings.search.editor.section.advanced")) {
                    Stepper(value: $key.priority, in: 0...100) {
                        HStack {
                            Text(L10n.text("ai_settings.search.editor.field.priority"))
                            Spacer()
                            Text("\(key.priority)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(L10n.text("ai_settings.field.enabled"), isOn: $key.isUsing)
                        .tint(.blue)
                }

                Section {
                    HStack {
                        Button(L10n.text("ai_settings.search.editor.action.test_api")) {
                            testAPI()
                        }
                        .disabled(isTesting || canTest == false)

                        Spacer()

                        if isTesting {
                            ProgressView()
                        } else if let testResult {
                            Text(testResult ? L10n.text("ai_settings.search.editor.test.passed") : L10n.text("ai_settings.search.editor.test.failed"))
                                .foregroundStyle(testResult ? .green : .red)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Section {
                    Text(L10n.text("ai_settings.search.editor.note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? L10n.text("ai_settings.search.editor.nav_add") : L10n.text("ai_settings.search.editor.nav_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.providers.editor.action.save")) {
                        guard validateForSave() else { return }
                        onSave(key)
                        dismiss()
                    }
                    .disabled(canSave == false)
                }
            }
            .onAppear {
                testResult = nil
            }
            .sheet(item: $helpPage) { page in
                SearchHelpWebSheet(page: page)
            }
        }
    }

    private var displayName: String {
        let name = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        let company = key.company.trimmingCharacters(in: .whitespacesAndNewlines)
        return company.isEmpty ? L10n.text("ai_settings.search.provider.generic") : company
    }

    private var canSave: Bool {
        key.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        key.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var canTest: Bool {
        canSave && key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func validateForSave() -> Bool {
        let endpoint = key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") else {
            errorMessage = L10n.text("ai_settings.search.error.endpoint_scheme")
            return false
        }
        if key.isUsing,
           SearchProviderID(company: key.company) != .spark,
           key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = String(format: L10n.text("ai_settings.search.error.need_api_key_format"), displayName)
            return false
        }
        errorMessage = nil
        return true
    }

    private func testAPI() {
        guard validateForSave(), let url = URL(string: key.requestURL) else { return }
        isTesting = true
        testResult = nil

        let config = SearchRuntimeConfig(
            provider: SearchProviderID(company: key.company),
            displayName: displayName,
            apiKey: key.key.trimmingCharacters(in: .whitespacesAndNewlines),
            requestURL: url,
            searchCount: 3,
            bilingualSearch: false,
            revision: SearchRuntimeConfigRevision(),
            rawKeyID: key.id
        )

        Task {
            do {
                let response = try await WebSearchGateway().search(query: "SparkClient", config: config)
                await MainActor.run {
                    testResult = response.items.isEmpty == false
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    testResult = false
                    isTesting = false
                }
            }
        }
    }
}

private struct SearchHelpWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: SearchHelpPage

    var body: some View {
        CompatibleNavigationContainer {
#if canImport(UIKit)
            SearchHelpSafariView(url: page.url)
                .ignoresSafeArea(edges: .bottom)
#else
            Text(page.url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
#endif
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.close")) {
                    dismiss()
                }
            }
        }
    }
}

#if canImport(UIKit)
private struct SearchHelpSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
