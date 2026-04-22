import SwiftUI

/// 各业务场景模型：以本地目录合成的 bundle 为准，显式默认写入 `scenarioDefaultModels`。
struct AIScenarioConfigEditorView: View {
    @Binding var snapshot: AISettingsSnapshot

    private var localBundles: AIScenarioRemoteBundlesCollection {
        snapshot.localScenarioBundles()
    }

    var body: some View {
        Form {
            ForEach(AIScenario.allCases, id: \.rawValue) { scenario in
                scenarioSection(title: scenario.localizedTitle, scenario: scenario)
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.scenario"))
    }

    @ViewBuilder
    private func scenarioSection(title: String, scenario: AIScenario) -> some View {
        let bundle = localBundles.bundle(for: scenario)
        Section(title) {
            if bundle.models.count > 1 {
                Picker(L10n.text("ai_settings.scenario_model_picker"), selection: scenarioModelSelection(for: scenario)) {
                    ForEach(bundle.models, id: \.model) { row in
                        Text(scenarioModelLabel(row)).tag(row.model)
                    }
                }
            }

            if let row = snapshot.resolveScenarioRow(for: scenario) {
                readOnlyField(title: L10n.text("ai_settings.endpoint"), value: row.endpoint)
                readOnlyField(title: L10n.text("ai_settings.model"), value: row.model)
                if let key = row.apiKey, key.isEmpty == false {
                    readOnlyField(
                        title: L10n.text("ai_settings.api_key"),
                        value: String(repeating: "•", count: min(key.count, 8))
                    )
                }
                readOnlyField(title: L10n.text("ai_settings.temperature"), value: String(format: "%.2f", row.temperature))
                readOnlyField(title: L10n.text("ai_settings.max_tokens"), value: "\(row.maxTokens)")
            } else {
                Text(L10n.text("ai_settings.scenario_model_picker"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func readOnlyField(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func scenarioModelLabel(_ row: AIScenarioRemoteModelRow) -> String {
        let suffix = row.isDefault ? " (\(L10n.text("ai_settings.scenario_default_hint")))" : ""
        return row.model + suffix
    }

    private func scenarioModelSelection(for scenario: AIScenario) -> Binding<String> {
        Binding(
            get: {
                snapshot.scenarioDefaultModelName(for: scenario)
                    ?? snapshot.resolveScenarioRow(for: scenario)?.model
                    ?? ""
            },
            set: { newValue in
                var next = snapshot
                next.setScenarioDefaultModelName(newValue, for: scenario)
                snapshot = next
            }
        )
    }
}

@MainActor
private struct AIScenarioConfigEditorViewPreviewHost: View {
    @State private var snapshot = AISettingsSnapshot.default

    var body: some View {
        CompatibleNavigationContainer {
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
