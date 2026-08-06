import SwiftUI

struct DeepTutorComposerReferenceBandView: View {
    let attachments: [DeepTutorAttachment]
    let references: [DeepTutorContextReference]

    private var hasContent: Bool {
        attachments.isEmpty == false || references.isEmpty == false
    }

    var body: some View {
        if hasContent {
            DeepTutorContextReferenceTreeView(
                attachments: attachments,
                references: references
            )
            .frame(maxWidth: min(560, UIScreen.main.bounds.width * 0.85), alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeepTutorPalette.mutedSurface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DeepTutorPalette.mutedBorderColor)
                    .frame(height: 1)
            }
        }
    }
}
