import SwiftUI

struct DeepTutorToolPreviewRelatedContentView: View {
    let items: [DeepTutorToolPreviewRelatedContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.primary)

                        Spacer(minLength: 0)

                        Text(item.kindLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    if let subtitle = item.subtitle, subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let body = item.body, body.isEmpty == false {
                        Text(body)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.78))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.badges.isEmpty == false {
                        FlexibleBadgeRow(items: item.badges)
                    }

                    if item.actions.isEmpty == false {
                        HStack(spacing: 10) {
                            ForEach(item.actions) { action in
                                HStack(spacing: 6) {
                                    if let systemImage = action.systemImage {
                                        Image(systemName: systemImage)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    Text(action.title)
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DeepTutorPalette.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DeepTutorPalette.borderColor.opacity(0.7), lineWidth: 1)
                )
                .deepTutorAskUserCardShadow()
            }
        }
    }
}

private struct FlexibleBadgeRow: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    badge(item)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    badge(item)
                }
            }
        }
    }

    private func badge(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
    }
}
