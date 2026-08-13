import SwiftUI

struct AIToolConsentSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    private let descriptors = ToolModelEgressConsentPolicy.managedDescriptors()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        L10n.text("ai_settings.tool_consent.title", fallback: "发送给 AI 授权"),
                        systemImage: "lock.shield"
                    )
                    .font(.headline)
                    Text(L10n.text(
                        "ai_settings.tool_consent.intro",
                        fallback: "管理工具结果在发送给模型前的授权策略。你可以统一配置默认行为，也可以对位置、天气、健康等敏感工具逐个设置。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(
                    L10n.text("ai_settings.tool_consent.default_mode", fallback: "默认策略"),
                    selection: defaultModeBinding
                ) {
                    ForEach(ToolModelEgressConsentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack(spacing: 10) {
                    consentModeBadge(defaultModeBinding.wrappedValue, emphasized: true)
                    Text(L10n.text(
                        "ai_settings.tool_consent.default_mode.footer",
                        fallback: "未单独配置的工具将继承这个默认策略。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text(L10n.text("ai_settings.tool_consent.section.general", fallback: "通用设置"))
            }

            Section {
                ForEach(descriptors, id: \.normalizedToolName) { descriptor in
                    NavigationLink {
                        AIToolConsentDetailView(
                            viewModel: viewModel,
                            descriptor: descriptor
                        )
                    } label: {
                        AIToolConsentCardView(
                            descriptor: descriptor,
                            preference: viewModel.snapshot.toolModelEgressConsentPreferences.preference(for: descriptor.toolName),
                            effectiveMode: viewModel.snapshot.toolModelEgressConsentPreferences.mode(for: descriptor.toolName),
                            defaultMode: viewModel.snapshot.toolModelEgressConsentPreferences.defaultMode
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                Text(L10n.text("ai_settings.tool_consent.section.management", fallback: "授权管理"))
            } footer: {
                Text(L10n.text(
                    "ai_settings.tool_consent.remote_only.footer",
                    fallback: "仅对会把敏感工具结果发送给远端模型的场景生效。本地模型默认不弹出这类出境授权。"
                ))
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.tool_consent", fallback: "授权管理"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var defaultModeBinding: Binding<ToolModelEgressConsentMode> {
        Binding {
            viewModel.snapshot.toolModelEgressConsentPreferences.defaultMode
        } set: { newValue in
            viewModel.snapshot.toolModelEgressConsentPreferences.defaultMode = newValue
            viewModel.snapshot.toolModelEgressConsentPreferences.normalize()
            Task { await viewModel.persistSnapshotNow() }
        }
    }
}

struct AIToolConsentDetailView: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let descriptor: ToolModelEgressConsentDescriptor

    private var currentPreference: ToolModelEgressConsentPreference? {
        viewModel.snapshot.toolModelEgressConsentPreferences.preference(for: descriptor.toolName)
    }

    private var effectiveMode: ToolModelEgressConsentMode {
        viewModel.snapshot.toolModelEgressConsentPreferences.mode(for: descriptor.toolName)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        AIToolConsentModeBadge(mode: effectiveMode, emphasized: true)
                        Text(
                            currentPreference == nil
                            ? L10n.text("ai_settings.tool_consent.follow_default", fallback: "跟随通用策略")
                            : L10n.text("ai_settings.tool_consent.custom", fallback: "单独配置")
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    Text(descriptor.summary)
                        .font(.body)
                    Text(descriptor.toolName)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(
                    L10n.text("ai_settings.tool_consent.picker.send_to_ai", fallback: "发送给 AI"),
                    selection: toolModeBinding
                ) {
                    Text(
                        L10n.format(
                            "ai_settings.tool_consent.picker.follow_default_format",
                            fallback: "跟随通用策略（%@）",
                            viewModel.snapshot.toolModelEgressConsentPreferences.defaultMode.displayName
                        )
                    )
                    .tag(Optional<ToolModelEgressConsentMode>.none)
                    ForEach(ToolModelEgressConsentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(Optional(mode))
                    }
                }

                if currentPreference != nil {
                    Button(
                        L10n.text("ai_settings.tool_consent.action.restore_default", fallback: "恢复跟随通用策略"),
                        role: .destructive
                    ) {
                        viewModel.snapshot.toolModelEgressConsentPreferences.clearPreference(for: descriptor.toolName)
                        Task { await viewModel.persistSnapshotNow() }
                    }
                }
            } header: {
                Text(L10n.text("ai_settings.tool_consent.section.policy", fallback: "授权策略"))
            } footer: {
                Text(
                    L10n.format(
                        "ai_settings.tool_consent.effective_mode_format",
                        fallback: "当前生效：%@。如果该工具没有单独配置，就会继承通用默认策略。",
                        effectiveMode.displayName
                    )
                )
            }

            Section {
                ForEach(descriptor.dataLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                        .font(.body)
                }
            } header: {
                Text(L10n.text("ai_settings.tool_consent.detail.data_to_authorize", fallback: "将会授权的数据"))
            }

            Section {
                ForEach(descriptor.dataSourceLines, id: \.self) { line in
                    Label(line, systemImage: "externaldrive.badge.icloud")
                        .font(.body)
                }
            } header: {
                Text(L10n.text("ai_settings.tool_consent.detail.data_sources", fallback: "数据来源"))
            }

            Section {
                Text(descriptor.whyItNeedsAI)
                    .font(.body)
                    .foregroundStyle(.primary)
            } header: {
                Text(L10n.text("ai_settings.tool_consent.detail.why_send_to_ai", fallback: "为什么需要发送给 AI"))
            }

            Section {
                Text(descriptor.denyImpact)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.text("ai_settings.tool_consent.detail.deny_impact", fallback: "拒绝后的影响"))
            }

            if let preference = currentPreference {
                Section {
                    if let provider = normalizedMetadata(preference.lastProviderCompany) {
                        metadataRow(
                            title: L10n.text("ai_settings.tool_consent.metadata.provider", fallback: "模型厂商"),
                            value: provider
                        )
                    }
                    if let modelName = normalizedMetadata(preference.lastModelName) {
                        metadataRow(
                            title: L10n.text("ai_settings.tool_consent.metadata.model", fallback: "模型名称"),
                            value: modelName
                        )
                    }
                    if let lastUsedAt = preference.lastUsedAt {
                        metadataRow(
                            title: L10n.text("ai_settings.tool_consent.metadata.last_sent", fallback: "最近发送"),
                            value: AIToolConsentFormatters.dateTime.string(from: lastUsedAt)
                        )
                    }
                    metadataRow(
                        title: L10n.text("ai_settings.tool_consent.metadata.updated_at", fallback: "配置更新时间"),
                        value: AIToolConsentFormatters.dateTime.string(from: preference.updatedAt)
                    )
                } header: {
                    Text(L10n.text("ai_settings.tool_consent.detail.recent_usage", fallback: "最近使用"))
                }
            }

            if descriptor.relatedToolNames.isEmpty == false {
                Section {
                    ForEach(descriptor.relatedToolNames, id: \.self) { toolName in
                        NavigationLink {
                            AIToolDetailDestinationView(toolName: toolName, viewModel: viewModel)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SparkToolName.displayName(for: toolName))
                                    .foregroundStyle(.primary)
                                Text(toolName)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.text("ai_settings.tool_consent.detail.related_tools", fallback: "关联工具"))
                }
            }
        }
        .navigationTitle(descriptor.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toolModeBinding: Binding<ToolModelEgressConsentMode?> {
        Binding {
            currentPreference?.mode
        } set: { newValue in
            if let newValue {
                viewModel.snapshot.toolModelEgressConsentPreferences.setMode(newValue, for: descriptor.toolName)
            } else {
                viewModel.snapshot.toolModelEgressConsentPreferences.clearPreference(for: descriptor.toolName)
            }
            Task { await viewModel.persistSnapshotNow() }
        }
    }

    @ViewBuilder
    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

private struct AIToolConsentCardView: View {
    let descriptor: ToolModelEgressConsentDescriptor
    let preference: ToolModelEgressConsentPreference?
    let effectiveMode: ToolModelEgressConsentMode
    let defaultMode: ToolModelEgressConsentMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(descriptor.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        AIToolConsentModeBadge(mode: effectiveMode, emphasized: true)
                    }

                    Text(descriptor.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        AIToolConsentAuxBadge(text: descriptor.categoryTitle, color: .secondary)
                        AIToolConsentAuxBadge(
                            text: preference == nil
                                ? L10n.text("ai_settings.tool_consent.follow_default.short", fallback: "跟随通用")
                                : L10n.text("ai_settings.tool_consent.custom", fallback: "单独配置"),
                            color: preference == nil ? .secondary : .blue
                        )
                    }

                    if preference == nil {
                        Text(
                            L10n.format(
                                "ai_settings.tool_consent.inherited_default_format",
                                fallback: "当前继承默认策略：%@",
                                defaultMode.shortDisplayName
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if let lastUsedAt = preference?.lastUsedAt {
                        Text(
                            L10n.format(
                                "ai_settings.tool_consent.last_sent_format",
                                fallback: "最近发送：%@",
                                AIToolConsentFormatters.dateTime.string(from: lastUsedAt)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var iconName: String {
        switch descriptor.category {
        case .location:
            return "location.fill"
        case .weather:
            return "cloud.sun.fill"
        case .health:
            return "heart.text.square.fill"
        }
    }

    private var iconColor: Color {
        switch descriptor.category {
        case .location:
            return .blue
        case .weather:
            return .cyan
        case .health:
            return .pink
        }
    }
}

struct AIToolConsentModeBadge: View {
    let mode: ToolModelEgressConsentMode
    var emphasized: Bool = false

    var body: some View {
        Text(mode.shortDisplayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(emphasized ? 0.18 : 0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch mode {
        case .alwaysAllow:
            return .green
        case .askEveryTime:
            return .orange
        case .alwaysDeny:
            return .red
        }
    }
}

private func consentModeBadge(_ mode: ToolModelEgressConsentMode, emphasized: Bool = false) -> some View {
    AIToolConsentModeBadge(mode: mode, emphasized: emphasized)
}

private enum AIToolConsentFormatters {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct AIToolConsentAuxBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
