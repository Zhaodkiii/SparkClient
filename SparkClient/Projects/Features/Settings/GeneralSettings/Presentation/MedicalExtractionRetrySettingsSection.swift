import SwiftUI

struct MedicalExtractionRetrySettingsSection: View {
    @State private var settings = MedicalExtractionRetrySettings.default
    private let store = MedicalExtractionRetrySettingsStore()

    var body: some View {
        Section {
            Toggle(isOn: autoRetryEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("settings.medical_extraction.auto_retry.title"))
                    Text(L10n.text("settings.medical_extraction.auto_retry.subtitle"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.autoRetryOnDecodingFailureEnabled {
                Stepper(
                    value: maxRetryCountBinding,
                    in: 1 ... 5
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("settings.medical_extraction.auto_retry.count_title"))
                        Text(
                            String(
                                format: L10n.text("settings.medical_extraction.auto_retry.count_value"),
                                settings.maxDecodingFailureAutoRetryCount
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        Text(L10n.text("settings.medical_extraction.auto_retry.count_subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(L10n.text("settings.medical_extraction.section_title"))
        }
        .onAppear {
            settings = store.load()
        }
    }

    private var autoRetryEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.autoRetryOnDecodingFailureEnabled },
            set: { newValue in
                settings.autoRetryOnDecodingFailureEnabled = newValue
                persist()
            }
        )
    }

    private var maxRetryCountBinding: Binding<Int> {
        Binding(
            get: { settings.maxDecodingFailureAutoRetryCount },
            set: { newValue in
                settings.maxDecodingFailureAutoRetryCount = newValue
                persist()
            }
        )
    }

    private func persist() {
        settings = settings.clamped()
        store.save(settings)
    }
}
