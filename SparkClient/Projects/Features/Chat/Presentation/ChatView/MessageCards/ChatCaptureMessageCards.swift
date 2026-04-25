import SwiftUI

struct ChatCaptureTypeMessageCard: View {
    let cardType: ChatCaptureCardType
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void
    let onOpenFiles: () -> Void

    var body: some View {
        let spec = CaptureCardSpec(cardType)
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(spec.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text(spec.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if spec.examples.isEmpty == false {
                HStack(spacing: 12) {
                    ForEach(spec.examples) { example in
                        exampleItem(title: example.title, icon: example.icon, tint: spec.tint)
                    }
                }
            }

            HStack(spacing: 10) {
                actionButton(icon: "camera.fill", title: L10n.text("chat.capture_card.action.camera"), color: spec.tint, action: onOpenCamera)
                actionButton(icon: "photo.on.rectangle", title: L10n.text("chat.capture_card.action.photo_library"), color: spec.tint, action: onOpenPhotoLibrary)
                if spec.supportsFiles {
                    actionButton(icon: "doc.fill", title: L10n.text("chat.capture_card.action.files"), color: spec.tint, action: onOpenFiles)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private func exampleItem(title: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 60)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureCardSpec {
    let title: String
    let subtitle: String
    let tint: Color
    let examples: [CaptureCardExample]
    let supportsFiles: Bool

    init(_ type: ChatCaptureCardType) {
        switch type {
        case .reportPhoto:
            title = L10n.text("chat.capture_card.report.title")
            subtitle = L10n.text("chat.capture_card.report.subtitle")
            tint = .blue
            examples = [
                CaptureCardExample(title: L10n.text("chat.capture_card.report.example.flat"), icon: "doc.text.fill"),
                CaptureCardExample(title: L10n.text("chat.capture_card.report.example.complete"), icon: "iphone")
            ]
            supportsFiles = true
        case .medicineBoxPhoto:
            title = L10n.text("chat.capture_card.medicine_box.title")
            subtitle = L10n.text("chat.capture_card.medicine_box.subtitle")
            tint = .purple
            examples = [
                CaptureCardExample(title: L10n.text("chat.capture_card.medicine_box.example.flat"), icon: "shippingbox"),
                CaptureCardExample(title: L10n.text("chat.capture_card.medicine_box.example.front"), icon: "iphone")
            ]
            supportsFiles = false
        case .skinPhoto:
            title = L10n.text("chat.capture_card.skin.title")
            subtitle = L10n.text("chat.capture_card.skin.subtitle")
            tint = .green
            examples = []
            supportsFiles = false
        }
    }
}

private struct CaptureCardExample: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}
