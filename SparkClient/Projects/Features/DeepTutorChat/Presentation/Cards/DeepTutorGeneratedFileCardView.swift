import SwiftUI

struct DeepTutorGeneratedFileCardView: View {
    let payload: DeepTutorGeneratedFilePayload

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.filename)
                    .font(.system(size: 14, weight: .semibold))
                if let mimeType = payload.mimeType {
                    Text(mimeType)
                        .font(.system(size: DeepTutorPalette.captionFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Open")
                .font(.system(size: DeepTutorPalette.captionFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(DeepTutorPalette.secondarySurface, in: cardShape)
        .deepTutorBubbleShadow()
        .padding(.vertical, 4)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.cardCornerRadius, style: .continuous)
    }

    private var iconName: String {
        if payload.mimeType?.hasPrefix("image/") == true { return "photo" }
        if payload.mimeType?.hasPrefix("video/") == true { return "play.rectangle" }
        return "doc"
    }
}
