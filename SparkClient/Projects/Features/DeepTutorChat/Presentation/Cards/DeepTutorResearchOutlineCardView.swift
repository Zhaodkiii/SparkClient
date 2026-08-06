import SwiftUI

struct DeepTutorResearchOutlineCardView: View {
    let payload: DeepTutorResearchOutlinePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(payload.title)
                .font(.system(size: 16, weight: .semibold))
            ForEach(payload.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let summary = section.summary {
                        Text(summary)
                            .font(.system(size: DeepTutorPalette.captionFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(DeepTutorPalette.secondarySurface, in: cardShape)
        .deepTutorBubbleShadow()
        .padding(.vertical, 4)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.cardCornerRadius, style: .continuous)
    }
}
