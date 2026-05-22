import SwiftUI

struct HanlinHealthResourceThumbnail: View {
    let ref: HealthResourceRef
    let index: Int
    let total: Int
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(
                            String(
                                format: L10n.text("chat.ask_report.strip.index_format"),
                                index,
                                total
                            )
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }

                    if let badge = ref.typeBadge, badge.isEmpty == false {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }

                    Text(ref.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if ref.displaySubtitle.isEmpty == false {
                        Text(ref.displaySubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(width: 132, height: 84, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .padding(4)
            .accessibilityLabel(L10n.text("chat.ask_report.strip.remove.accessibility"))
        }
    }
}
