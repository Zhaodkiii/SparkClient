import SwiftUI

struct DeepTutorThinkingCardView: View {
    let text: String

    var body: some View {
        DeepTutorMarkdownRenderer(markdown: text)
            .font(.system(size: DeepTutorPalette.captionFontSize))
            .italic()
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}
