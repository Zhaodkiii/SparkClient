import SwiftUI

/// 默认模型配置页：按场景统一展示，支持本地模型与 Pro 模型切换。
struct AIModelPreferencesView: View {
    let aiConfigCenter: AIConfigCenter?

    @State private var localBundles: AIScenarioRemoteBundlesCollection?
    @State private var proBundles: AIScenarioRemoteBundlesCollection?
    @State private var mergedBundles: AIScenarioRemoteBundlesCollection?
    @State private var pendingSelections: [String: String] = [:]

    var body: some View {
        Form {
            ForEach(AIScenario.allCases, id: \.rawValue) { scenario in
                scenarioSection(scenario)
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.default_model_config"))
        .task {
            await reloadBundles()
        }
    }

    @ViewBuilder
    private func scenarioSection(_ scenario: AIScenario) -> some View {
        let source = sourceBinding(for: scenario).wrappedValue
        let proBundle = proBundles?.bundle(for: scenario)
        let hasProModels = (proBundle?.models.isEmpty == false)
        let activeBundle = bundle(for: scenario, source: source)

        Section(header: Text(scenario.localizedTitle)) {
            scenarioIntro(for: scenario)

            if hasProModels {
                Picker(L10n.text("ai_settings.prefs.source_config"), selection: sourceBinding(for: scenario)) {
                    Text(L10n.text("ai_settings.prefs.source_local_key")).tag(AIModelSelectionSource.localKey)
                    Text(L10n.text("ai_settings.prefs.source_trial")).tag(AIModelSelectionSource.trial)
                }
                .pickerStyle(.segmented)
            }

            if let activeBundle, activeBundle.models.isEmpty == false {
                let selected = modelSelectionBinding(for: scenario, sourceBundle: activeBundle)
                Picker(L10n.text("ai_settings.scenario_model_picker"), selection: selected) {
                    Text(L10n.text("ai_settings.prefs.model_unselected")).tag("")
                    ForEach(activeBundle.models, id: \.model) { row in
                        Text(bundleRowDisplayName(row)).tag(row.model)
                    }
                }

                if let picked = activeBundle.models.first(where: { $0.model == selected.wrappedValue }) {
                    modelSummaryRow(
                        company: companyLabelForBundleRow(picked),
                        displayName: bundleRowDisplayName(picked),
                        subtitle: picked.model
                    )
                }
            } else {
                Text(L10n.text("ai_settings.no_models_configure_key"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bundle(for scenario: AIScenario, source: AIModelSelectionSource) -> AIScenarioRemoteBundle? {
        switch source {
        case .localKey:
            return localBundles?.bundle(for: scenario)
        case .trial:
            return proBundles?.bundle(for: scenario)
        }
    }

    private func sourceBinding(for scenario: AIScenario) -> Binding<AIModelSelectionSource> {
        Binding(
            get: {
                let stored = AIScenarioModelSourceStore.read(for: scenario) ?? .localKey
                if stored == .trial,
                   proBundles?.bundle(for: scenario).models.isEmpty != false
                {
                    return .localKey
                }
                return stored
            },
            set: { newValue in
                AIScenarioModelSourceStore.write(newValue, for: scenario)
                pendingSelections[scenario.rawValue] = ""
            }
        )
    }

    private func modelSelectionBinding(for scenario: AIScenario, sourceBundle: AIScenarioRemoteBundle) -> Binding<String> {
        Binding(
            get: {
                if let pending = pendingSelections[scenario.rawValue] {
                    return pending
                }
                if let stored = AIScenarioDefaultModelStore.read(for: scenario),
                   sourceBundle.models.contains(where: { $0.model == stored })
                {
                    return stored
                }
                let mergedDefault = mergedBundles?.bundle(for: scenario).defaultModelName ?? ""
                if mergedDefault.isEmpty == false,
                   sourceBundle.models.contains(where: { $0.model == mergedDefault })
                {
                    return mergedDefault
                }
                if sourceBundle.defaultModelName.isEmpty == false,
                   sourceBundle.models.contains(where: { $0.model == sourceBundle.defaultModelName })
                {
                    return sourceBundle.defaultModelName
                }
                return sourceBundle.models.first?.model ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingSelections[scenario.rawValue] = trimmed
                guard trimmed.isEmpty == false else { return }
                AIScenarioDefaultModelStore.write(trimmed, for: scenario)
                Task {
                    await aiConfigCenter?.updateScenarioDefaultModel(trimmed, for: scenario)
                    await reloadBundles()
                }
            }
        )
    }

    private func reloadBundles() async {
        guard let aiConfigCenter else {
            localBundles = nil
            proBundles = nil
            mergedBundles = nil
            return
        }
        async let local = aiConfigCenter.localScenarioBundles()
        async let pro = aiConfigCenter.proScenarioBundles()
        async let merged = try? aiConfigCenter.effectiveScenarioBundles()
        localBundles = await local
        proBundles = await pro
        mergedBundles = await merged
    }

    private func bundleRowDisplayName(_ row: AIScenarioRemoteModelRow) -> String {
        row.displayName.isEmpty ? row.model : row.displayName
    }

    private func companyLabelForBundleRow(_ row: AIScenarioRemoteModelRow) -> String {
        if let company = row.providerCompany, company.isEmpty == false {
            return company
        }
        return ""
    }

    @ViewBuilder
    private func scenarioIntro(for scenario: AIScenario) -> some View {
        VStack(alignment: .center) {
            Image(systemName: scenario.introIconSystemName)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, 4)

            Text(scenario.localizedIntro)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func modelSummaryRow(company: String, displayName: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(companyIconName(for: company))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct AIModelPreferencesViewPreviewHost: View {
    var body: some View {
        NavigationView {
            AIModelPreferencesView(aiConfigCenter: nil)
        }
    }
}

@MainActor
struct AIModelPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.light)

            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.dark)
        }
    }
}
