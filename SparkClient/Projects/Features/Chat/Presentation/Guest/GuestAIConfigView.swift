import SwiftUI

struct GuestAIConfigView: View {
    @Binding var config: GuestAIConfig?
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var errorMessage: String?

    private let presetProviders: [(nameKey: String, baseURL: String, model: String)] = [
        ("guest.config.preset.openai", "https://api.openai.com/v1", "gpt-4o-mini"),
        ("guest.config.preset.deepseek", "https://api.deepseek.com/v1", "deepseek-chat"),
        ("guest.config.preset.doubao", "https://ark.cn-beijing.volces.com/api/v3", "doubao-seed-2-0-pro-260215"),
        ("guest.config.preset.qwen", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-turbo"),
    ]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(presetProviders, id: \.nameKey) { provider in
                        Button {
                            baseURL = provider.baseURL
                            model = provider.model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.text(provider.nameKey))
                                        .foregroundStyle(.primary)
                                    Text(provider.baseURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if baseURL == provider.baseURL {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L10n.text("guest.config.quick_select"))
                }

                Section {
                    TextField(L10n.text("guest.config.base_url"), text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField(L10n.text("guest.config.model"), text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Group {
                            if showAPIKey {
                                TextField(L10n.text("guest.config.api_key"), text: $apiKey)
                            } else {
                                SecureField(L10n.text("guest.config.api_key"), text: $apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.text("guest.config.custom"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.text("guest.config.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("guest.config.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("guest.config.save")) {
                        saveConfig()
                    }
                    .disabled(isValid == false)
                }
            }
            .onAppear {
                if let config {
                    baseURL = config.baseURL
                    model = config.model
                    apiKey = config.apiKey
                }
            }
        }
    }

    private var isValid: Bool {
        draftConfig?.isValid == true
    }

    private var draftConfig: GuestAIConfig? {
        GuestAIConfig(
            provider: .openAICompatible,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func saveConfig() {
        errorMessage = nil

        guard draftConfig?.chatCompletionsURL != nil else {
            errorMessage = L10n.text("guest.config.err.invalid_url")
            return
        }
        guard model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            errorMessage = L10n.text("guest.config.err.empty_model")
            return
        }
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            errorMessage = L10n.text("guest.config.err.empty_api_key")
            return
        }
        guard let newConfig = draftConfig, newConfig.isValid else {
            errorMessage = L10n.text("guest.config.err.invalid")
            return
        }

        config = newConfig
        dismiss()
    }
}
