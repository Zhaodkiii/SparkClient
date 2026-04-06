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
                            systemImage: "sparkles"
                        ) {
                            selectedModelName = nil
                        }

                        ForEach(models, id: \.model) { row in
                            modelButton(
                                title: row.pickerLabel,
                                isSelected: selectedModelName == row.model,
                                systemImage: "cpu"
                            ) {
                                selectedModelName = row.model
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
            }
        }
    }

    private func modelButton(
        title: String,
        isSelected: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray))
                    .frame(width: 20, height: 20)

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

private extension AIScenarioRemoteModelRow {
    var pickerLabel: String {
        if let name = providerName, name.isEmpty == false {
            return name
        }
        if let id = identity, id.isEmpty == false {
            return "\(model) · \(id)"
        }
        return model
    }
}
