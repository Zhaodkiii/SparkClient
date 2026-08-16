import SwiftUI

/// 专业版模型横滑（使用系统语义色，不依赖固定品牌色）。
struct ChatComposerModelPickerRow: View {
    let models: [AIScenarioRemoteModelRow]
    @Binding var selectedModelName: String?

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
