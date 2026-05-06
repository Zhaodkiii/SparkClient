import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var isTesting = false
    @State private var testPassed: Bool?
    @State private var testErrorMessage: String?
    @State private var selectedTestModelName = ""
    @State private var showDeleteModelAlert = false
    @State private var pendingDeleteModelID: UUID?
    @State private var presentedSheet: ProviderSettingsSheet?
    @State private var showNoticeAlert = false
    @State private var noticeMessage = ""
    private let probeService = ClientModelCapabilityProbeService()

    private var providerModels: [AllModels] {
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model }
            .filter { $0.providerID == provider.providerID }
            .sorted { $0.position < $1.position }
    }

    private var testableModels: [AllModels] {
        providerModels
            .filter(\.supportsTextGen)
            .filter(\.isEnabled)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text("ai_settings.providers.editor.field.provider"))
                    Spacer()
                    Text(L10n.text(provider.localizedDisplayName))
                        .foregroundStyle(.secondary)
                }
                TextField(L10n.text("ai_settings.providers.editor.field.request_url"), text: $provider.requestURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(L10n.text("ai_settings.providers.editor.field.api_key"), text: $provider.key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                if provider.privacyPolicyURL.isEmpty == false {
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
            Section(L10n.text("ai_settings.providers.editor.section.api_test")) {
                if testableModels.isEmpty == false {
                    Picker(L10n.text("ai_settings.providers.editor.field.test_model"), selection: $selectedTestModelName) {
                        ForEach(testableModels) { model in
                            Text(model.displayName)
                                .tag(model.name)
                        }
                    }
                }

                HStack {
                    Button(L10n.text("ai_settings.providers.editor.action.test_api")) {
                        Task {
                            await testProvider()
                        }
                    }
                    .disabled(isTesting || testableModels.isEmpty)

                    Spacer()
                    if isTesting {
                        ProgressView()
                    } else if let passed = testPassed {
                        Text(L10n.text(passed ? "ai_settings.providers.editor.test.passed" : "ai_settings.providers.editor.test.failed"))
                            .foregroundStyle(passed ? .green : .red)
                    } else if testableModels.isEmpty {
                        Text(L10n.text("ai_settings.providers.editor.test.no_models"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let testErrorMessage, testErrorMessage.isEmpty == false {
                    Text(testErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Text(L10n.text("ai_settings.providers.editor.footer.auto_enable_notice"))
                    .font(.footnote)
            }
        }
        .navigationTitle(L10n.text("ai_settings.providers.editor.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("common.save")) {
                    if provider.privacyPolicyURL.isEmpty == false, provider.privacyPolicyAccepted == false {
                        return
                    }
                    saveProvider()
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
        .confirmationDialog(
            L10n.text("ai_settings.providers.editor.alert.delete_model_title"),
            isPresented: $showDeleteModelAlert,
            titleVisibility: .visible
        ) {
            Button(L10n.text("common.delete"), role: .destructive) {
                guard let id = pendingDeleteModelID else { return }
                deleteModel(modelID: id)
                pendingDeleteModelID = nil
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                pendingDeleteModelID = nil
            }
        } message: {
            Text(L10n.text("ai_settings.providers.editor.alert.delete_model_message"))
        }
        .alert(L10n.text("ai_settings.providers.editor.alert.notice_title"), isPresented: $showNoticeAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
        .onAppear(perform: syncSelectedTestModel)
        .onChange(of: testableModels) { _ in
            syncSelectedTestModel()
        }
    }

    private func deleteModel(modelID: UUID) {
        impact(.light)
        Task {
            let ok = await viewModel.deleteModelAndPersist(id: modelID)
            if ok == false, let message = viewModel.errorMessage {
                showNotice(message)
            }
        }
    }

    private func saveProvider() {
        impact(.medium)
        Task {
            _ = await viewModel.saveProviderFromEditorAndPersist(provider)
        }
        dismiss()
    }

    private func testProvider() async {
        let key = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else {
            showNotice(L10n.text("ai_settings.providers.editor.alert.need_api_key"))
            testPassed = false
            return
        }
        guard let modelName = resolvedTestModelName else {
            let message = L10n.text("ai_settings.providers.editor.alert.no_models")
            testPassed = false
            testErrorMessage = message
            showNotice(message)
            return
        }

        isTesting = true
        testErrorMessage = nil
        defer { isTesting = false }

        let backendResult = await viewModel.testProviderConnection(
            requestURL: provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: key,
            model: modelName
        )
        if backendResult.reachable {
            testPassed = true
            testErrorMessage = nil
            impact(.medium)
            return
        }

        if backendResult.message?.lowercased() == "network_error" {
            do {
                var localProvider = provider
                localProvider.key = key
                localProvider.requestURL = provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
                try await probeService.testConnection(modelName: modelName, provider: localProvider)
                testPassed = true
                testErrorMessage = nil
                impact(.medium)
                return
            } catch {
                let message = error.localizedDescription
                testPassed = false
                testErrorMessage = message
                showNotice(message)
                return
            }
        }

        let message = backendFailureMessage(rawMessage: backendResult.message)
        testPassed = false
        testErrorMessage = message
        showNotice(message)
    }

    private var resolvedTestModelName: String? {
        if testableModels.contains(where: { $0.name == selectedTestModelName }) {
            return selectedTestModelName
        }
        return testableModels.first?.name
    }

    private func syncSelectedTestModel() {
        guard let modelName = resolvedTestModelName else {
            selectedTestModelName = ""
            return
        }
        if selectedTestModelName != modelName {
            selectedTestModelName = modelName
        }
    }

    private func backendFailureMessage(rawMessage: String?) -> String {
        let trimmed = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else {
            return L10n.text("ai_settings.providers.editor.alert.test_failed")
        }
        switch trimmed.lowercased() {
        case "network_error":
            return L10n.text("ai_settings.providers.editor.alert.backend_network_error")
        default:
            return trimmed
        }
    }

    private func showNotice(_ message: String) {
        noticeMessage = message
        showNoticeAlert = true
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
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
