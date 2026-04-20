import SwiftUI

private enum ProviderSettingsSheet: Identifiable {
    case manageModels

    var id: String {
        switch self {
        case .manageModels:
            return "manageModels"
        }
    }
}

struct ProviderSettingsEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State var provider: APIKeys
    let viewModel: AISettingsViewModel
    let onDeleteModel: (UUID) -> Void
    let onSave: (APIKeys) -> Void
    let onTest: (APIKeys) async -> Bool

    @State private var isTesting = false
    @State private var testPassed: Bool?
    @State private var showDeleteModelAlert = false
    @State private var pendingDeleteModelID: UUID?
    @State private var presentedSheet: ProviderSettingsSheet?

    private var providerModels: [AllModels] {
        let company = provider.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model }
            .filter { $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text("ai_settings.providers.editor.field.provider"))
                    Spacer()
                    Text(provider.displayName)
                        .foregroundStyle(.secondary)
                }
                TextField(L10n.text("ai_settings.providers.editor.field.request_url"), text: $provider.requestURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(L10n.text("ai_settings.providers.editor.field.api_key"), text: $provider.key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if provider.source == .custom {
                Section(L10n.text("ai_settings.providers.editor.section.custom")) {
                    TextField(L10n.text("ai_settings.providers.editor.field.custom_name"), text: $provider.name)
                }
            }

            Section {
                if providerModels.isEmpty {
                    Text(L10n.text("ai_settings.providers.editor.models.empty"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(providerModels) { model in
                        ModelsSettingsMainRow(
                            model: model,
                            viewModel: viewModel,
                            isEditing: false,
                            priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                            priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                            onDelete: {
                                pendingDeleteModelID = model.id
                                showDeleteModelAlert = true
                            },
                            showsInfoButton: true,
                            showsLeadingSwipeAction: true
                        )
                    }
                }
            } header: {
                HStack {
                    Text(L10n.text("ai_settings.providers.editor.section.models"))
                    Spacer()
                    Button {
                        presentedSheet = .manageModels
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            if provider.privacyPolicyURL.isEmpty == false {
                Section(L10n.text("ai_settings.providers.editor.section.privacy")) {
                    if let url = URL(string: provider.privacyPolicyURL) {
                        Link(L10n.text("ai_settings.providers.editor.privacy.view_policy"), destination: url)
                            .font(.footnote)
                    }
                    Toggle(isOn: $provider.privacyPolicyAccepted) {
                        Text(L10n.text("ai_settings.providers.editor.privacy.accept"))
                            .font(.footnote)
                    }
                    .tint(.accentColor)
                }
            }

            Section {
                Button {
                    Task {
                        isTesting = true
                        defer { isTesting = false }
                        testPassed = await onTest(provider)
                    }
                } label: {
                    HStack {
                        Text(L10n.text("ai_settings.providers.editor.action.test_api"))
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let passed = testPassed {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(passed ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.providers.editor.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("ai_settings.providers.editor.action.save")) {
                    if provider.privacyPolicyURL.isEmpty == false, provider.privacyPolicyAccepted == false {
                        return
                    }
                    provider.privacyPolicyAcceptedAt = provider.privacyPolicyAccepted ? Date() : nil
                    onSave(provider)
                    dismiss()
                }
                .disabled(provider.privacyPolicyURL.isEmpty == false && provider.privacyPolicyAccepted == false)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .manageModels:
                ModelManagementView(provider: provider, viewModel: viewModel)
            }
        }
        .alert(L10n.text("ai_settings.providers.editor.alert.delete_model_title"), isPresented: $showDeleteModelAlert) {
            Button(L10n.text("common.cancel"), role: .cancel) {
                pendingDeleteModelID = nil
            }
            Button(L10n.text("common.delete"), role: .destructive) {
                guard let id = pendingDeleteModelID else { return }
                onDeleteModel(id)
                pendingDeleteModelID = nil
            }
        } message: {
            Text(L10n.text("ai_settings.providers.editor.alert.delete_model_message"))
        }
    }
}

extension APIKeys {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        return company
    }

    var localizedDisplayName: String {
        if source == .custom {
            return displayName
        }
        let key = "company_\(company.uppercased())"
        let localized = L10n.text(key)
        return localized == key ? displayName : localized
    }
}
