import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct APIKeysSettingsView: View {
    @Binding var snapshot: AISettingsSnapshot
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var showAddCustomProvider = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var trialPrivacyAccepted = false

    private var sortedProviders: [APIKeys] {
        let filtered = snapshot.apiKeys.filter { $0.company.uppercased() != "LOCAL" }
        let grouped = Dictionary(grouping: filtered, by: { $0.company.uppercased() })
        return grouped.values
            .compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var isSignedIn: Bool {
        // API settings页只在登录会话中出现；保持保守判定，避免出现误导按钮。
        true
    }

    private var trialProviders: [APIKeys] {
        guard snapshot.trial.isActive else { return [] }

        let endpoints = Set(snapshot.trialModelPolicy.map { $0.config.endpoint.lowercased() })
        let list = snapshot.apiKeys.filter { provider in
            endpoints.contains(provider.requestURL.lowercased())
        }
        let grouped = Dictionary(grouping: list, by: { $0.company.uppercased() })
        return grouped.values.compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                trialEntryCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if snapshot.trial.isActive, trialProviders.isEmpty == false {
                Section(L10n.text("ai_settings.providers.section.trial_providers")) {
                    ForEach(trialProviders) { provider in
                        HStack(spacing: 12) {
                            Image(companyIconName(for: provider.company))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text(provider.localizedDisplayName)
                                .font(.body)
                            Spacer()
                            Text(L10n.text("ai_settings.providers.badge.trial"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.text("ai_settings.providers.trial_providers.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text("ai_settings.providers.section.providers")) {
                ForEach(sortedProviders) { provider in
                    providerRow(provider)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showAddCustomProvider = true
                } label: {
                  Image(systemName: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.providers.nav_title"))
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showAddCustomProvider) {
            AddCustomProviderSheet { newProvider in
                snapshot.apiKeys.append(newProvider)
                impact(.medium)
                Task { await viewModel.persistSnapshotNow() }
            }
        }
        .alert(L10n.text("ai_settings.providers.editor.alert.notice_title"), isPresented: $showErrorAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await viewModel.refreshTrialStatus()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.apiKeys)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.trial)
    }

    private var trialEntryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "key.radiowaves.forward.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("ai_settings.providers.trial.card.title"))
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(L10n.text("ai_settings.providers.trial.card.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                trialConsentArea
                trialActionButton
            }

            modelBadges
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var statusLabel: some View {
        Group {
            switch snapshot.trial.status {
            case "active":
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L10n.text("ai_settings.providers.trial.status.active"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if snapshot.trial.remainingSeconds > 0 {
                        Text(String(format: L10n.text("ai_settings.providers.trial.status.remaining_days"), daysRemaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            case "pending":
                Label(L10n.text("ai_settings.providers.trial.status.pending"), systemImage: "clock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            case "rejected":
                Label(L10n.text("ai_settings.providers.trial.status.rejected"), systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            case "expired":
                Label(L10n.text("ai_settings.providers.trial.status.expired"), systemImage: "hourglass.bottomhalf.filled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            default:
                Label(L10n.text("ai_settings.providers.trial.status.default"), systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var daysRemaining: Int {
        max(Int(ceil(Double(snapshot.trial.remainingSeconds) / 86_400.0)), 0)
    }

    private var trialConsentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("ai_settings.providers.trial.consent.hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle(isOn: $trialPrivacyAccepted) {
                Text(L10n.text("ai_settings.providers.trial.consent.toggle"))
                    .font(.footnote)
            }
            .tint(.accentColor)
        }
    }

    private var trialActionButton: some View {
        Button {
            guard trialPrivacyAccepted else {
                showError(L10n.text("ai_settings.providers.trial.error.need_consent"))
                return
            }
            Task {
                let ok = await viewModel.submitTrialApplication()
                if ok {
                    impact(.medium)
                }
            }
        } label: {
            HStack {
                if viewModel.trialOperationInFlight {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Text(trialButtonTitle)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.trialOperationInFlight || !isSignedIn)
    }

    private var trialButtonTitle: String {
        switch snapshot.trial.status {
        case "active": return L10n.text("ai_settings.providers.trial.action.active")
        case "pending": return L10n.text("ai_settings.providers.trial.action.pending")
        case "rejected", "expired": return L10n.text("ai_settings.providers.trial.action.reapply")
        default: return L10n.text("ai_settings.providers.trial.action.apply")
        }
    }

    private var modelBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["OpenAI", "Gemini", "Claude", "DeepSeek", "GLM"], id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func providerRow(_ provider: APIKeys) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProviderSettingsEditorView(
                    provider: provider,
                    viewModel: viewModel
                )
            } label: {
                HStack(spacing: 12) {
                    Image(companyIconName(for: provider.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(provider.localizedDisplayName)
                        .font(.body)
                    Spacer()
                    if provider.source == .custom {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("", isOn: Binding(
                get: { provider.isHidden == false },
                set: { newValue in
                    setProviderEnabled(providerID: provider.id, enabled: newValue)
                }
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
    }

    private func setProviderEnabled(providerID: UUID, enabled: Bool) {
        guard let index = snapshot.apiKeys.firstIndex(where: { $0.id == providerID }) else { return }
        let provider = snapshot.apiKeys[index]

        if enabled && provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError(String(format: L10n.text("ai_settings.providers.error.key_required_with_name"), provider.localizedDisplayName))
            return
        }

        snapshot.apiKeys[index].isHidden = !enabled
        snapshot.apiKeys[index].timestamp = Date()
        updateModelVisibility(company: provider.company, hidden: !enabled)
        impact(.light)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func updateModelVisibility(company: String, hidden: Bool) {
        for index in snapshot.allModels.indices where snapshot.allModels[index].company.uppercased() == company.uppercased() {
            snapshot.allModels[index].isHidden = hidden
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private struct AddCustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var key = ""
    @State private var requestURL = ""
    @State private var errorMessage: String?

    let onSave: (APIKeys) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.text("ai_settings.providers.add.field.name"), text: $name)
                    SecureField(L10n.text("ai_settings.providers.editor.field.api_key"), text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(L10n.text("ai_settings.providers.editor.field.request_url"), text: $requestURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    if requestURL.isEmpty == false, requestURL.hasSuffix("/v1/chat/completions") == false {
                        Button(L10n.text("ai_settings.providers.add.action.append_completion_path")) {
                            var base = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            while base.hasSuffix("/") { base.removeLast() }
                            requestURL = "\(base)/v1/chat/completions"
                        }
                        .font(.footnote)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(L10n.text("ai_settings.providers.add.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.providers.editor.action.save")) {
                        guard validate() else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedCompany = "CUSTOM_\(UUID().uuidString.prefix(8).uppercased())"
                        let provider = APIKeys(
                            name: trimmedName,
                            company: normalizedCompany,
                            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                            requestURL: requestURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            isHidden: false,
                            help: L10n.text("ai_settings.providers.add.help"),
                            source: .custom,
                            timestamp: Date()
                        )
                        onSave(provider)
                        dismiss()
                    }
                    .disabled(!isBasicInputFilled)
                }
            }
        }
    }

    private var isBasicInputFilled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func validate() -> Bool {
        let url = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            errorMessage = L10n.text("ai_settings.providers.add.error.invalid_url_prefix")
            return false
        }
        errorMessage = nil
        return true
    }
}
