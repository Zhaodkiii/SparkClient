import SwiftUI

public struct Theme: Sendable {
    public var textColor: Color
    public var linkColor: Color
    public var bodyFont: Font
    public var codeFont: Font
    public var codeForegroundColor: Color
    public var codeBackgroundColor: Color
    public var blockSpacing: CGFloat

    public init(
        textColor: Color = .primary,
        linkColor: Color = .accentColor,
        bodyFont: Font = .body,
        codeFont: Font = .system(.footnote, design: .monospaced),
        codeForegroundColor: Color = .primary,
        codeBackgroundColor: Color = Color.primary.opacity(0.08),
        blockSpacing: CGFloat = 8
    ) {
        self.textColor = textColor
        self.linkColor = linkColor
        self.bodyFont = bodyFont
        self.codeFont = codeFont
        self.codeForegroundColor = codeForegroundColor
        self.codeBackgroundColor = codeBackgroundColor
        self.blockSpacing = blockSpacing
    }
}

public extension Theme {
    static let basic = Theme()

    static let gitHub = Theme(
        textColor: .primary,
        linkColor: .blue,
        bodyFont: .body,
        codeFont: .system(.footnote, design: .monospaced),
        codeForegroundColor: .primary,
        codeBackgroundColor: Color(red: 0.95, green: 0.96, blue: 0.97),
        blockSpacing: 8
    )

    static func chatBubble(foreground: Color) -> Theme {
        Theme(
            textColor: foreground,
            linkColor: foreground.opacity(0.9),
            bodyFont: .body,
            codeFont: .system(.footnote, design: .monospaced),
            codeForegroundColor: foreground,
            codeBackgroundColor: foreground.opacity(0.14),
            blockSpacing: 8
        )
    }
}

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .basic
}

public extension EnvironmentValues {
    var markdownTheme: Theme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
}

public extension View {
    func markdownTheme(_ theme: Theme) -> some View {
        environment(\.markdownTheme, theme)
    }
}
