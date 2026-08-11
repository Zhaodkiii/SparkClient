import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum WeatherEnquiryPalette {
    static let background = Color(red: 244 / 255, green: 244 / 255, blue: 248 / 255)
    static let card = Color.white
    static let primaryText = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    static let secondaryText = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let divider = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
}

private struct WeatherToolKeyEditorContext: Identifiable {
    let id: UUID
    var key: ToolKeys

    init(key: ToolKeys) {
        self.id = key.id
        self.key = key
    }
}

private func weatherProviderValidationError(for key: ToolKeys, displayName: String) -> String? {
    guard key.toolClass.lowercased() == "weather" else {
        return L10n.text("ai_settings.weather.error.invalid_class", fallback: "仅支持天气类供应商。")
    }
    guard let provider = WeatherProviderID.parse(company: key.company) else {
        return L10n.format("ai_settings.weather.error.unsupported_provider_format", displayName)
    }
    if provider.isReserved {
        return L10n.format("ai_settings.weather.error.reserved_provider_format", displayName)
    }
    guard provider.hasLocalAdapter else {
        return L10n.format("ai_settings.weather.error.unsupported_provider_format", displayName)
    }
    if provider.usesAPIKey {
        if key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.format("ai_settings.weather.error.need_api_key_format", displayName)
        }
        if key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           WeatherEndpointNormalizer.isValidEndpoint(requestURL: key.requestURL, provider: provider) == false {
            return L10n.format("ai_settings.weather.error.invalid_endpoint_format", displayName)
        }
    }
    return nil
}

private func providerAdapterAvailable(_ key: ToolKeys) -> Bool {
    guard let provider = WeatherProviderID.parse(company: key.company) else { return false }
    return provider.hasLocalAdapter
}

struct AIWeatherToolSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @State private var editorContext: WeatherToolKeyEditorContext?
    @State private var errorMessage: String?

    private var preferences: AIWeatherToolPreferences {
        viewModel.snapshot.weatherToolPreferences
    }

    private var sortedWeatherKeys: [ToolKeys] {
        let keys = viewModel.snapshot.toolKeys.filter { key in
            key.toolClass.lowercased() == "weather"
                && WeatherToolKeysMigration.canonicalCompany(key.company) != nil
        }
        let order = WeatherToolKeysMigration.requiredCompanies
        return keys.sorted {
            let lhs = order.firstIndex(of: WeatherToolKeysMigration.canonicalCompany($0.company) ?? "") ?? Int.max
            let rhs = order.firstIndex(of: WeatherToolKeysMigration.canonicalCompany($1.company) ?? "") ?? Int.max
            if lhs == rhs { return $0.company.localizedStandardCompare($1.company) == .orderedAscending }
            return lhs < rhs
        }
    }

    private var activeWeatherKeyID: UUID? {
        WeatherRuntimeConfigResolver.activeWeatherKey(from: viewModel.snapshot)?.id
    }

    var body: some View {
        ZStack {
            WeatherEnquiryPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    enableWeatherCard
                    sectionTitle(L10n.text("ai_settings.weather.section.providers", fallback: "Weather service provider selection (only one can be enabled)"))
                    providerCard
                    AIWeatherPreviewPanel(snapshot: viewModel.snapshot)
                    sectionTitle(L10n.text("ai_settings.weather.section.capabilities", fallback: "Function List"))
                    functionListCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(L10n.text("ai_settings.weather.nav_title", fallback: "Weather Enquiry"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(item: $editorContext) { context in
            WeatherToolKeyEditorView(
                initialKey: context.key,
                onSave: { key in
                    saveToolKey(key)
                }
            )
        }
        .alert(L10n.text("common.notice", fallback: "Notice"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { presented in
                if presented == false { errorMessage = nil }
            }
        )) {
            Button(L10n.text("common.ok", fallback: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var introCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(WeatherEnquiryPalette.accent)
            Text(L10n.text("ai_settings.weather.intro", fallback: "Configure weather tools so supported models can retrieve real-time weather and short-range forecasts in chats. Results are never fabricated when providers are unavailable."))
                .font(.footnote)
                .foregroundStyle(WeatherEnquiryPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .weatherEnquiryCard()
    }

    private var enableWeatherCard: some View {
        HStack {
            Text(L10n.text("ai_settings.weather.enable", fallback: "Enable Weather"))
                .font(.body.weight(.semibold))
                .foregroundStyle(WeatherEnquiryPalette.primaryText)
            Spacer()
            Toggle("", isOn: preferenceBinding(\.useWeather))
                .labelsHidden()
                .tint(WeatherEnquiryPalette.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .weatherEnquiryCard()
    }

    private var providerCard: some View {
        VStack(spacing: 0) {
            if sortedWeatherKeys.isEmpty {
                Text(L10n.text("ai_settings.weather.empty_providers", fallback: "No weather providers"))
                    .font(.footnote)
                    .foregroundStyle(WeatherEnquiryPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                ForEach(Array(sortedWeatherKeys.enumerated()), id: \.element.id) { index, key in
                    if index > 0 {
                        Divider().overlay(WeatherEnquiryPalette.divider).padding(.leading, 68)
                    }
                    weatherProviderRow(for: key)
                }
            }
        }
        .weatherEnquiryCard()
    }

    private var functionListCard: some View {
        VStack(spacing: 0) {
            functionRow(
                title: L10n.text("ai_settings.weather.capability.realtime", fallback: "Check Real-time Weather"),
                icon: "cloud.sun"
            )
            Divider().overlay(WeatherEnquiryPalette.divider).padding(.leading, 52)
            functionRow(
                title: L10n.text("ai_settings.weather.capability.forecast", fallback: "Future Weather Forecast"),
                icon: "calendar"
            )
        }
        .weatherEnquiryCard()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WeatherEnquiryPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func functionRow(title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(WeatherEnquiryPalette.accent)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(WeatherEnquiryPalette.primaryText)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
    }

    private func weatherProviderRow(for key: ToolKeys) -> some View {
        let adapterAvailable = providerAdapterAvailable(key)
        let provider = WeatherProviderID.parse(company: key.company)
        return HStack(spacing: 12) {
            Button {
                editorContext = WeatherToolKeyEditorContext(key: key)
            } label: {
                HStack(spacing: 14) {
                    providerIcon(for: key)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(displayName(for: key))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WeatherEnquiryPalette.primaryText)
                            if key.id == activeWeatherKeyID, preferences.useWeather {
                                statusBadge(
                                    L10n.text("ai_settings.weather.provider.active", fallback: "Active"),
                                    color: WeatherEnquiryPalette.accent
                                )
                            } else if adapterAvailable == false {
                                statusBadge(
                                    L10n.text("ai_settings.weather.provider.coming_soon", fallback: "Coming soon"),
                                    color: .orange
                                )
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if provider?.usesAPIKey == true {
                        Image(systemName: hasAPIKey(key) ? "key.fill" : "key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(hasAPIKey(key) ? WeatherEnquiryPalette.accent : WeatherEnquiryPalette.secondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { key.isUsing },
                set: { enabled in
                    setWeatherProviderEnabled(id: key.id, enabled: enabled)
                }
            ))
            .labelsHidden()
            .tint(WeatherEnquiryPalette.accent)
            .disabled(adapterAvailable == false || preferences.useWeather == false)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 72)
        .opacity(preferences.useWeather ? 1 : 0.55)
    }

    @ViewBuilder
    private func providerIcon(for key: ToolKeys) -> some View {
        let asset = companyIconName(for: key.company)
        if UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(WeatherEnquiryPalette.accent)
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func saveToolKey(_ key: ToolKeys) {
        var next = key
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.company = next.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        next.key = next.key.trimmingCharacters(in: .whitespacesAndNewlines)
        next.requestURL = next.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        next.toolClass = "weather"
        next.timestamp = Date()

        Task { @MainActor in
            _ = await viewModel.upsertWeatherToolKeyAndPersist(next)
        }
    }

    private func setWeatherProviderEnabled(id: UUID, enabled: Bool) {
        guard preferences.useWeather else {
            errorMessage = L10n.text("ai_settings.weather.error.enable_switch_first", fallback: "Turn on Enable Weather first.")
            return
        }
        guard let selected = sortedWeatherKeys.first(where: { $0.id == id }) else { return }
        if providerAdapterAvailable(selected) == false {
            errorMessage = L10n.format("ai_settings.weather.error.reserved_provider_format", displayName(for: selected))
            return
        }
        if enabled, let validationError = weatherProviderValidationError(for: selected, displayName: displayName(for: selected)) {
            errorMessage = validationError
            return
        }

        Task { @MainActor in
            _ = await viewModel.setWeatherProviderEnabledAndPersist(id: id, enabled: enabled)
        }
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<AIWeatherToolPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { value in
                Task { @MainActor in
                    var next = viewModel.snapshot.weatherToolPreferences
                    next[keyPath: keyPath] = value
                    _ = await viewModel.updateWeatherToolPreferencesAndPersist(next)
                }
            }
        )
    }

    private func displayName(for key: ToolKeys) -> String {
        WeatherToolKeysMigration.displayName(for: key)
    }

    private func hasAPIKey(_ key: ToolKeys) -> Bool {
        key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private struct WeatherEnquiryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WeatherEnquiryPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private extension View {
    func weatherEnquiryCard() -> some View {
        modifier(WeatherEnquiryCardModifier())
    }
}

private struct WeatherToolKeyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key: ToolKeys
    let onSave: (ToolKeys) -> Void

    private var provider: WeatherProviderID? {
        WeatherProviderID.parse(company: key.company)
    }

    init(initialKey: ToolKeys, onSave: @escaping (ToolKeys) -> Void) {
        _key = State(initialValue: initialKey)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        Image(companyIconName(for: key.company))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .padding(.top, 4)

                        if provider?.usesAPIKey == false {
                            Text(L10n.text("ai_settings.weather.editor.apple_intro", fallback: "Apple Weather uses WeatherKit on this device. No API key is required when WeatherKit is available."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else if provider?.hasLocalAdapter == false {
                            Text(L10n.format("ai_settings.weather.error.reserved_provider_format", displayName))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(L10n.format("ai_settings.weather.editor.intro_format", displayName))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if let url = helpURL {
                            Link(
                                provider?.usesAPIKey == false
                                    ? L10n.text("ai_settings.weather.editor.view_docs", fallback: "View documentation")
                                    : L10n.format("ai_settings.weather.editor.help_link_format", displayName),
                                destination: url
                            )
                            .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                if provider?.usesAPIKey == true, provider?.hasLocalAdapter == true {
                    Section(L10n.text("ai_settings.weather.editor.key_section", fallback: "API Key")) {
                        SecureField(L10n.text("ai_settings.weather.editor.key_placeholder", fallback: "Enter API Key"), text: $key.key)
                    }

                    Section(L10n.text("ai_settings.weather.editor.endpoint_section", fallback: "Request URL")) {
                        TextField(L10n.text("ai_settings.weather.editor.endpoint_placeholder", fallback: "Enter request URL"), text: $key.requestURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }
            }
            .navigationTitle(displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", fallback: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(provider?.usesAPIKey == true ? L10n.text("common.save", fallback: "Save") : L10n.text("common.ok", fallback: "OK")) {
                        if provider?.usesAPIKey == true {
                            onSave(key)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var displayName: String {
        let name = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? key.company : name
    }

    private var helpURL: URL? {
        let trimmed = key.help.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else { return nil }
        return URL(string: trimmed)
    }
}
