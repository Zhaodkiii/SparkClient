import MarkdownUI
import SwiftUI

struct DeepTutorMarkdownRenderer: View {
    let markdown: String

    var body: some View {
        MarkdownUI.Markdown(markdown)
            .markdownTheme(MarkdownUI.Theme.gitHub)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
