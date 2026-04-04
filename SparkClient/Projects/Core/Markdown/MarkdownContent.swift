import Foundation

public protocol MarkdownContentProtocol {
    var _markdownContent: MarkdownContent { get }
}

public struct MarkdownContent: Equatable, Sendable, MarkdownContentProtocol {
    public let markdown: String

    public var _markdownContent: MarkdownContent { self }

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public init(@MarkdownContentBuilder content: () -> MarkdownContent) {
        self = content()
    }
}

@resultBuilder
public enum MarkdownContentBuilder {
    public static func buildBlock(_ components: MarkdownContentProtocol...) -> MarkdownContent {
        MarkdownContent(components.map(\._markdownContent.markdown).joined(separator: "\n"))
    }

    public static func buildExpression(_ expression: MarkdownContentProtocol) -> MarkdownContent {
        expression._markdownContent
    }

    public static func buildExpression(_ expression: String) -> MarkdownContent {
        MarkdownContent(expression)
    }

    public static func buildArray(_ components: [MarkdownContentProtocol]) -> MarkdownContent {
        MarkdownContent(components.map(\._markdownContent.markdown).joined(separator: "\n"))
    }

    public static func buildOptional(_ component: MarkdownContentProtocol?) -> MarkdownContent {
        component?._markdownContent ?? MarkdownContent("")
    }

    public static func buildEither(first component: MarkdownContentProtocol) -> MarkdownContent {
        component._markdownContent
    }

    public static func buildEither(second component: MarkdownContentProtocol) -> MarkdownContent {
        component._markdownContent
    }
}
