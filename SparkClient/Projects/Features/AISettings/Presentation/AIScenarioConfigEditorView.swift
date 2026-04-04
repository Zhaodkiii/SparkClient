import SwiftUI

struct AIScenarioConfigEditorView: View {
    @Binding var snapshot: AISettingsSnapshot

    var body: some View {
        Form {
            scenarioSection(
                title: L10n.text("ai_settings.scenario.medical_extraction"),
                config: $snapshot.medicalExtraction
            )
            scenarioSection(
                title: L10n.text("ai_settings.scenario.embedding"),
                config: $snapshot.embedding
            )
        }
        .navigationTitle(L10n.text("ai_settings.row.scenario"))
    }

    @ViewBuilder
    private func scenarioSection(title: String, config: Binding<AIScenarioConfig>) -> some View {
        Section(title) {
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
}
