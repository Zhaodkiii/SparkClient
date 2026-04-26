import SwiftUI

struct ChatThreadSettingsSheet: View {
    let modelOptions: [AIScenarioRemoteModelRow]
    let currentModelSupportsMultimodal: Bool
    let onUpdate: @Sendable (ChatThreadGenerationSettings) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: ChatThreadGenerationSettings

    init(
        modelOptions: [AIScenarioRemoteModelRow],
        initialSettings: ChatThreadGenerationSettings,
        currentModelSupportsMultimodal: Bool,
        onUpdate: @escaping @Sendable (ChatThreadGenerationSettings) async -> Void
    ) {
        self.modelOptions = modelOptions
        self.currentModelSupportsMultimodal = currentModelSupportsMultimodal
        self.onUpdate = onUpdate
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modelPickerCard
                    systemPromptCard

                    ChatThreadSettingCard(
                        title: L10n.text("chat.settings.temperature.title"),
                        subtitle: L10n.text("chat.settings.temperature.subtitle"),
                        systemImage: "thermometer.variable",
                        options: temperatureOptions,
                        selection: $settings.temperature
                    )

                    ChatThreadSettingCard(
                        title: L10n.text("chat.settings.top_p.title"),
                        subtitle: L10n.text("chat.settings.top_p.subtitle"),
                        systemImage: "percent",
                        options: topPOptions,
                        selection: $settings.topP
                    )

                    ChatThreadSettingCard(
                        title: L10n.text("chat.settings.max_tokens.title"),
                        subtitle: L10n.text("chat.settings.max_tokens.subtitle"),
                        systemImage: "textformat.size",
                        options: maxTokenOptions,
                        selection: $settings.maxTokens
                    )

                    ChatThreadSettingCard(
                        title: L10n.text("chat.settings.max_messages.title"),
                        subtitle: L10n.text("chat.settings.max_messages.subtitle"),
                        systemImage: "message.badge",
                        options: maxMessageOptions,
                        selection: $settings.maxMessages
                    )

                    ChatThreadSettingCard(
                        title: L10n.text("chat.settings.image_delivery.title"),
                        subtitle: L10n.text("chat.settings.image_delivery.subtitle"),
                        systemImage: "photo.on.rectangle.angled",
                        options: imageDeliveryOptions,
                        selection: $settings.imageDeliveryMode
                    )
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text("chat.settings.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("chat.settings.action.close")) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: settings) { value in
            let snapshot = value
            Task { @MainActor in
                await onUpdate(snapshot)
            }
        }
    }

    private var modelPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("chat.settings.model.title"), systemImage: "cpu")
                .font(.headline)

            Text(L10n.text("chat.settings.model.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L10n.text("chat.settings.model.title"), selection: $settings.currentModelName) {
                Text(L10n.text("chat.composer.model.default")).tag(String?.none)
                ForEach(modelOptions) { option in
                    Text(option.displayTitle).tag(Optional(option.name))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var systemPromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("会话系统提示词")
                    .font(.headline)
            } icon: {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Color.accentColor)
            }

            Text("默认使用 Spark 健康助手提示词；当当前模型是智能体或触发小任务时，会按小任务 > 智能体 > 会话的优先级生效。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $settings.rolePrompt)
                .font(.body)
                .frame(minHeight: 120)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("恢复默认") {
                settings.rolePrompt = PromptLocalizer().chatSystemPrompt()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
        )
    }

    private var temperatureOptions: [ChatThreadSettingOption<Double>] {
        stride(from: 0.1, through: 2.0, by: 0.1).map { raw in
            let value = Double(round(raw * 10) / 10)
            return ChatThreadSettingOption(
                id: String(format: "temp-%.1f", value),
                value: value,
                title: String(format: "%.1f", value),
                detail: value < 0.7
                    ? L10n.text("chat.settings.temperature.detail.low")
                    : (value > 1.2 ? L10n.text("chat.settings.temperature.detail.high") : L10n.text("chat.settings.temperature.detail.medium"))
            )
        }
    }

    private var topPOptions: [ChatThreadSettingOption<Double>] {
        stride(from: 0.1, through: 1.0, by: 0.1).map { raw in
            let value = Double(round(raw * 10) / 10)
            return ChatThreadSettingOption(
                id: String(format: "top-p-%.1f", value),
                value: value,
                title: String(format: "%.1f", value),
                detail: value < 0.5
                    ? L10n.text("chat.settings.top_p.detail.low")
                    : (value > 0.8 ? L10n.text("chat.settings.top_p.detail.high") : L10n.text("chat.settings.top_p.detail.medium"))
            )
        }
    }

    private var maxTokenOptions: [ChatThreadSettingOption<Int>] {
        [256, 512, 1024, 2048, 4096, 8192, 16384, 32768].map { value in
            ChatThreadSettingOption(
                id: "tokens-\(value)",
                value: value,
                title: "\(value)",
                detail: String(format: L10n.text("chat.settings.max_tokens.detail"), locale: Locale.current, value)
            )
        }
    }

    private var maxMessageOptions: [ChatThreadSettingOption<Int>] {
        [5, 10, 20, 30, 40, 50, 60].map { value in
            ChatThreadSettingOption(
                id: "messages-\(value)",
                value: value,
                title: "\(value)",
                detail: String(format: L10n.text("chat.settings.max_messages.detail"), locale: Locale.current, value)
            )
        }
    }

    private var imageDeliveryOptions: [ChatThreadSettingOption<ChatThreadImageDeliveryMode>] {
        [
            ChatThreadSettingOption(
                id: ChatThreadImageDeliveryMode.directMultimodal.rawValue,
                value: .directMultimodal,
                title: L10n.text("chat.image_delivery.direct"),
                detail: currentModelSupportsMultimodal
                    ? L10n.text("chat.settings.image_delivery.detail.direct")
                    : L10n.text("chat.image_delivery.unavailable_hint")
            ),
            ChatThreadSettingOption(
                id: ChatThreadImageDeliveryMode.localOCR.rawValue,
                value: .localOCR,
                title: L10n.text("chat.image_delivery.ocr_only"),
                detail: L10n.text("chat.settings.image_delivery.detail.ocr")
            )
        ]
    }
}
