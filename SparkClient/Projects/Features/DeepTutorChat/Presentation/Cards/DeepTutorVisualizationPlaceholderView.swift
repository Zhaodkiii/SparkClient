import SwiftUI

struct DeepTutorVisualizationPlaceholderView: View {
    let payload: DeepTutorVisualizationPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(payload.title, systemImage: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .semibold))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 160)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(payload.snapshotDescription)
                            .font(.system(size: DeepTutorPalette.captionFontSize))
                            .foregroundStyle(.secondary)
                        Text("Local placeholder")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
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
