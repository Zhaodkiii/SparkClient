import SwiftUI

public struct Markdown: View {
    @Environment(\.markdownTheme) private var theme

    private let content: MarkdownContent
    private let baseURL: URL?
    private let imageBaseURL: URL?

    public init(_ content: MarkdownContent, baseURL: URL? = nil, imageBaseURL: URL? = nil) {
        self.content = content
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL ?? baseURL
    }

    public init(_ markdown: String, baseURL: URL? = nil, imageBaseURL: URL? = nil) {
        self.init(MarkdownContent(markdown), baseURL: baseURL, imageBaseURL: imageBaseURL)
    }

    public init(baseURL: URL? = nil, imageBaseURL: URL? = nil, @MarkdownContentBuilder content: () -> MarkdownContent) {
        self.init(content(), baseURL: baseURL, imageBaseURL: imageBaseURL)
    }

    public var body: some View {
        _ = baseURL
        _ = imageBaseURL
        return MarkdownDocumentView(
            text: content.markdown,
            style: makeDocumentStyle(from: theme)
        )
    }

    private func makeDocumentStyle(from theme: Theme) -> MarkdownDocumentStyle {
        MarkdownDocumentStyle(
            textColor: theme.textColor,
            secondaryTextColor: theme.textColor.opacity(0.78),
            headingColor: theme.textColor,
            linkColor: theme.linkColor,
            codeBackgroundColor: theme.codeBackgroundColor,
            quoteBarColor: theme.linkColor.opacity(0.75),
            quoteBackgroundColor: theme.codeBackgroundColor.opacity(0.55),
            tableBorderColor: theme.textColor.opacity(0.3),
            tableHeaderBackgroundColor: theme.codeBackgroundColor.opacity(0.7),
            paragraphSpacing: 8,
            blockSpacing: theme.blockSpacing
        )
    }
}
