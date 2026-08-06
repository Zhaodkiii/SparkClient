import SwiftUI

struct DeepTutorMarkdownRenderer: View {
    let markdown: String

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.chatBubble(foreground: .primary))
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
