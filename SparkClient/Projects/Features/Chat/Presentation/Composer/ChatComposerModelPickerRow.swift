import SwiftUI

/// 专业版模型横滑（使用系统语义色，不依赖固定品牌色）。
struct ChatComposerModelPickerRow: View {
    let models: [AIScenarioRemoteModelRow]
    @Binding var selectedModelName: String?
    /// CHAT-000058：医院会话单项锁定模式 —— 只展示当前医生智能体，
    /// 置灰、不可点击、不可展开，不提供“默认模型”入口（C-004）。
    var isSelectionLocked: Bool = false

    var body: some View {
        Group {
            if models.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L10n.text("chat.composer.model.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            } else if isSelectionLocked {
                HStack(spacing: 6) {
                    ForEach(models) { row in
                        lockedModelItem(row)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        modelButton(
                            title: L10n.text("chat.composer.model.default"),
                            isSelected: selectedModelName == nil,
                            icon: .system("sparkles")
                        ) {
                            selectedModelName = nil
                        }

                        ForEach(models) { row in
                            modelButton(
                                title: row.displayTitle,
                                isSelected: selectedModelName == row.name,
                                icon: composerIcon(for: row)
                            ) {
                                selectedModelName = row.name
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
            }
        }
    }

    /// CHAT-000058：锁定单项 —— 置灰展示、无点击动作、无展开/切换。
    private func lockedModelItem(_ row: AIScenarioRemoteModelRow) -> some View {
        HStack(spacing: 6) {
            modelLeadingIcon(icon: composerIcon(for: row), isSelected: false)
            Text(row.displayTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.text(
                "chat.composer.model.hospital_locked_a11y",
                fallback: "当前医生智能体 \(row.displayTitle)，已固定，不可切换"
            )
        )
    }

    private enum ComposerModelIcon {
        case system(String)
        case company(String)
    }

    private func composerIcon(for row: AIScenarioRemoteModelRow) -> ComposerModelIcon {
        let customIcon = row.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if customIcon.isEmpty == false {
            return .system(customIcon)
        }
        return .company(row.company)
    }

    private func modelButton(
        title: String,
        isSelected: Bool,
        icon: ComposerModelIcon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                modelLeadingIcon(icon: icon, isSelected: isSelected)

                if isSelected {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(10)
            .background(modelBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modelLeadingIcon(icon: ComposerModelIcon, isSelected: Bool) -> some View {
        switch icon {
        case .system(let systemName):
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray))
                .scaleEffect(isSelected ? 1.2 : 1.0)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5),
                    value: isSelected
                )
        case .company(let company):
            if isSelected {
                Image(companyIconName(for: company))
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.2)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5),
                        value: isSelected
                    )
            } else {
                Image(companyIconName(for: company))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color(.systemGray))
                    .scaleEffect(1.0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5),
                        value: isSelected
                    )
            }
        }
    }

    private func modelBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.12),
                        Color.accentColor.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(.secondarySystemFill)
            }
        }
    }
}
