import SwiftUI

struct AITriageGuideCardView: View {
    let payload: AITriageGuideCardPayload
    let onPromptTap: (AITriageGuidePrompt) -> Void

    private var accent: Color { Color.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(payload.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Text(payload.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(payload.prompts) { prompt in
                    Button {
                        onPromptTap(prompt)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: prompt.id))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                                .frame(width: 28)
                            Text(prompt.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("快捷症状，\(prompt.title)")
                }
            }

            Label(payload.disclaimer, systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        }
    }

    private func iconName(for promptID: String) -> String {
        switch promptID {
        case "headache": return "brain.head.profile"
        case "chest": return "heart.fill"
        case "stomach": return "fork.knife"
        default: return "text.bubble"
        }
    }
}
