import SwiftUI

struct AIScenarioConfigEditorView: View {
    @Binding var snapshot: AISettingsSnapshot

    var body: some View {
        Form {
            scenarioSection(title: L10n.text("ai_settings.scenario.chat"), scenario: .chat, config: $snapshot.chat)
            scenarioSection(
                title: L10n.text("ai_settings.scenario.optimization_text"),
                scenario: .optimizationText,
                config: $snapshot.optimizationText
            )
            scenarioSection(
                title: L10n.text("ai_settings.scenario.optimization_visual"),
                scenario: .optimizationVisual,
                config: $snapshot.optimizationVisual
            )
            scenarioSection(
                title: L10n.text("ai_settings.scenario.context_folding"),
                scenario: .contextFolding,
                config: $snapshot.contextFolding
            )
            scenarioSection(title: L10n.text("ai_settings.scenario.router"), scenario: .router, config: $snapshot.router)
            scenarioSection(
                title: L10n.text("ai_settings.scenario.model_config"),
                scenario: .modelConfig,
                config: $snapshot.modelConfig
            )
            scenarioSection(
                title: L10n.text("ai_settings.scenario.report_interpretation"),
                scenario: .reportInterpretation,
                config: $snapshot.reportInterpretation
            )
        }
        .navigationTitle(L10n.text("ai_settings.row.scenario"))
    }

    @ViewBuilder
    private func scenarioSection(title: String, scenario: AIScenario, config: Binding<AIScenarioConfig>) -> some View {
        Section(title) {
            if let bundle = snapshot.scenarioRemoteBundles?.bundle(for: scenario), bundle.models.count > 1 {
                Picker(L10n.text("ai_settings.scenario_model_picker"), selection: scenarioModelSelection(for: scenario)) {
                    ForEach(bundle.models, id: \.model) { row in
                        Text(scenarioModelLabel(row)).tag(row.model)
                    }
                }
            }

            TextField(
                L10n.text("ai_settings.endpoint"),
                text: config.endpoint
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField(
                L10n.text("ai_settings.model"),
                text: config.model
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField(
                L10n.text("ai_settings.api_key"),
                text: Binding(
                    get: { config.wrappedValue.apiKey ?? "" },
                    set: { config.wrappedValue.apiKey = $0.isEmpty ? nil : $0 }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            HStack {
                Text(L10n.text("ai_settings.temperature"))
                Spacer()
                Text(String(format: "%.2f", config.wrappedValue.temperature))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: config.temperature,
                in: 0.0...2.0,
                step: 0.05
            )

            Stepper(
                value: config.maxTokens,
                in: 128...32768,
                step: 128
            ) {
                HStack {
                    Text(L10n.text("ai_settings.max_tokens"))
                    Spacer()
                    Text("\(config.wrappedValue.maxTokens)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scenarioModelLabel(_ row: AIScenarioRemoteModelRow) -> String {
        let suffix = row.isDefault ? " (\(L10n.text("ai_settings.scenario_default_hint")))" : ""
        return row.model + suffix
    }

    private func scenarioModelSelection(for scenario: AIScenario) -> Binding<String> {
        Binding(
            get: {
                let bundle = snapshot.scenarioRemoteBundles?.bundle(for: scenario)
                return snapshot.scenarioSelectedModel[scenario.rawValue]
                    ?? bundle?.resolveRow(preferredModelName: nil)?.model
                    ?? ""
            },
            set: { newValue in
                var next = snapshot
                next.scenarioSelectedModel[scenario.rawValue] = newValue
                next.materializeAllScenariosFromBundles()
                snapshot = next
            }
        )
    }
}

@MainActor
private struct AIScenarioConfigEditorViewPreviewHost: View {
    @State private var snapshot = AISettingsSnapshot.default

    var body: some View {
        NavigationView {
            AIScenarioConfigEditorView(snapshot: $snapshot)
        }
    }
}

@MainActor
struct AIScenarioConfigEditorView_Previews: PreviewProvider {
    static var previews: some View {
        AIScenarioConfigEditorViewPreviewHost()
    }
}
