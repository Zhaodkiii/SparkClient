import SwiftUI

struct ChatMedicalRiskNoticeCardView: View {
    let payload: ChatMedicalRiskNoticePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(accentColor)
                    .imageScale(.medium)
                Text(payload.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(payload.riskLevelLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.12))
                    )
            }

            Text(payload.displayMessage)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let action = payload.recommendedAction?.trimmingCharacters(in: .whitespacesAndNewlines),
               action.isEmpty == false {
                HStack(alignment: .top, spacing: 6) {
                    Text(L10n.text("chat.medical_risk_notice.recommended_action"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(action)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: payload.riskLevel == .emergency ? 1.5 : 1)
        )
    }

    private var iconName: String {
        switch payload.riskLevel {
        case .low:
            return "info.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high, .emergency:
            return "cross.case.fill"
        }
    }

    private var accentColor: Color {
        switch payload.riskLevel {
        case .low:
            return .secondary
        case .medium:
            return .orange
        case .high:
            return .red
        case .emergency:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch payload.riskLevel {
        case .low:
            return Color(uiColor: .tertiarySystemFill)
        case .medium:
            return Color.orange.opacity(0.08)
        case .high:
            return Color.red.opacity(0.08)
        case .emergency:
            return Color.red.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch payload.riskLevel {
        case .low:
            return Color.secondary.opacity(0.2)
        case .medium:
            return Color.orange.opacity(0.35)
        case .high, .emergency:
            return Color.red.opacity(payload.riskLevel == .emergency ? 0.55 : 0.35)
        }
    }
}
