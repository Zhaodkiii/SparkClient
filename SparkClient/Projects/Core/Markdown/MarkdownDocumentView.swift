import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MarkdownDocumentStyle: Sendable {
    let textColor: Color
    let secondaryTextColor: Color
    let headingColor: Color
    let linkColor: Color
    let backgroundColor: Color
    let codeBackgroundColor: Color
    let codeForegroundColor: Color
    let quoteBarColor: Color
    let quoteBackgroundColor: Color
    let tableBorderColor: Color
    let tableHeaderBackgroundColor: Color
    let tableAlternateBackgroundColor: Color
    let dividerColor: Color
    let bodyFont: Font
    let codeFont: Font
    let paragraphSpacing: CGFloat
    let blockSpacing: CGFloat

    static let documentation = MarkdownDocumentStyle(
        textColor: .primary,
        secondaryTextColor: .secondary,
        headingColor: .primary,
        linkColor: .accentColor,
        backgroundColor: .clear,
        codeBackgroundColor: Color.primary.opacity(0.08),
        codeForegroundColor: .primary,
        quoteBarColor: .accentColor,
        quoteBackgroundColor: Color.accentColor.opacity(0.08),
        tableBorderColor: Color.secondary.opacity(0.25),
        tableHeaderBackgroundColor: Color.secondary.opacity(0.12),
        tableAlternateBackgroundColor: Color.secondary.opacity(0.06),
        dividerColor: Color.secondary.opacity(0.25),
        bodyFont: .body,
        codeFont: .system(.footnote, design: .monospaced),
        paragraphSpacing: 8,
        blockSpacing: 10
    )

    static func chatBubble(textColor: Color) -> MarkdownDocumentStyle {
        MarkdownDocumentStyle(
            textColor: textColor,
            secondaryTextColor: textColor.opacity(0.78),
            headingColor: textColor,
            linkColor: textColor,
            backgroundColor: .clear,
            codeBackgroundColor: textColor.opacity(0.12),
            codeForegroundColor: textColor,
            quoteBarColor: textColor.opacity(0.75),
            quoteBackgroundColor: textColor.opacity(0.08),
            tableBorderColor: textColor.opacity(0.3),
            tableHeaderBackgroundColor: textColor.opacity(0.12),
            tableAlternateBackgroundColor: textColor.opacity(0.06),
            dividerColor: textColor.opacity(0.24),
            bodyFont: .body,
            codeFont: .system(.footnote, design: .monospaced),
            paragraphSpacing: 6,
            blockSpacing: 8
        )
    }
}

struct MarkdownDocumentView: View {
    @Environment(\.markdownCodeSyntaxHighlighter) private var codeSyntaxHighlighter
    @Environment(\.markdownSoftBreakMode) private var softBreakMode

    private let segments: [MarkdownSegment]
    private let style: MarkdownDocumentStyle
    private let baseURL: URL?
    private let imageBaseURL: URL?

    init(
        text: String,
        style: MarkdownDocumentStyle = .documentation,
        baseURL: URL? = nil,
        imageBaseURL: URL? = nil
    ) {
        self.segments = MarkdownSegmentParser.parse(text)
        self.style = style
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL ?? baseURL
    }

    init(
        segments: [MarkdownSegment],
        style: MarkdownDocumentStyle = .documentation,
        baseURL: URL? = nil,
        imageBaseURL: URL? = nil
    ) {
        self.segments = segments
        self.style = style
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL ?? baseURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                render(segment)
            }
        }
        .foregroundStyle(style.textColor)
        .background(style.backgroundColor)
    }

    private func render(_ segment: MarkdownSegment) -> AnyView {
        switch segment {
        case .heading(let level, let text):
            return AnyView(heading(text, level: level))

        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: style.bodyFont, color: style.textColor)
                .lineSpacing(4)
                .padding(.bottom, 8))

        case .image(let alt, let source):
            return AnyView(markdownImage(alt: alt, source: source))

        case .unorderedList(let items):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: bulletMarker(for: item.level), content: item.content, level: item.level)
                }
            }
            .padding(.bottom, 8))

        case .orderedList(let items, let start):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let number = item.number ?? (start + index)
                    listRow(marker: "\(number).", content: item.content, level: item.level)
                }
            }
            .padding(.bottom, 8))

        case .taskList(let items):
            return AnyView(VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isDone ? style.linkColor : style.secondaryTextColor)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                            renderListContent(item.content)
                        }
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }
            .padding(.bottom, 8))

        case .blockquote(let children):
            return AnyView(HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.quoteBarColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        render(child, colorOverride: style.secondaryTextColor)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.quoteBackgroundColor)
            )
            .padding(.bottom, 8))

        case .codeBlock(let language, let code):
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                if let language, language.isEmpty == false {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style.secondaryTextColor)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlightedCode(code, language: language))
                        .font(style.codeFont)
                        .foregroundStyle(style.codeForegroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style.codeBackgroundColor)
            )
            .padding(.bottom, 8))

        case .table(let header, let alignments, let rows):
            return AnyView(ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    tableRow(cells: header, alignments: alignments, row: 0)
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        tableRow(cells: row, alignments: alignments, row: rowIndex + 1)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .stroke(style.tableBorderColor, lineWidth: 1)
                )
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [Color.clear, style.backgroundColor.opacity(0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 14)
                .allowsHitTesting(false)
            }
            .padding(.bottom, 8))

        case .htmlBlock(let html):
            return AnyView(Text(html.strippingHTMLTags())
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryTextColor)
                .textSelection(.enabled)
                .padding(.bottom, 8))

        case .thematicBreak:
            return AnyView(Divider()
                .frame(height: 3)
                .overlay(style.dividerColor)
                .padding(.vertical, 20))
        }
    }

    private func heading(_ text: String, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            markdownInlineFlow(text, font: headingFont(level: level), color: level == 6 ? style.secondaryTextColor : style.headingColor)
                .lineSpacing(3)
                .padding(.top, level <= 2 ? 16 : 12)
                .padding(.bottom, level <= 2 ? 8 : 6)
            if level <= 2 {
                Divider().overlay(style.dividerColor)
            }
        }
        .padding(.bottom, 8)
    }

    private func listRow(marker: String, content: [MarkdownSegment], level: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(style.bodyFont.weight(.semibold))
                .foregroundStyle(style.textColor)
                .frame(minWidth: 22, alignment: .trailing)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                renderListContent(content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(level) * 18)
    }

    private func renderListContent(_ content: [MarkdownSegment]) -> some View {
        ForEach(Array(content.enumerated()), id: \.offset) { index, child in
            renderListChild(child, isFirst: index == 0)
        }
    }

    private func renderListChild(_ segment: MarkdownSegment, isFirst: Bool) -> AnyView {
        switch segment {
        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: style.bodyFont, color: style.textColor)
                .lineSpacing(4)
                .padding(.bottom, isFirst ? 0 : 4))
        default:
            return render(segment)
        }
    }

    private func tableRow(cells: [String], alignments: [MarkdownSegment.TableAlignment], row: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                let alignment = tableCellAlignment(alignments[safe: column] ?? .leading)
                markdownInlineFlow(
                    cell,
                    font: row == 0 ? style.bodyFont.weight(.semibold) : style.bodyFont,
                    color: style.textColor
                )
                .frame(minWidth: 120, maxWidth: 260, alignment: alignment)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(style.tableBorderColor)
                        .frame(width: 1)
                }
            }
        }
        .background(row == 0 ? style.tableHeaderBackgroundColor : row.isMultiple(of: 2) ? style.tableAlternateBackgroundColor : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.tableBorderColor)
                .frame(height: 1)
        }
    }

    private func tableCellAlignment(_ alignment: MarkdownSegment.TableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func render(_ segment: MarkdownSegment, colorOverride: Color?) -> AnyView {
        let originalStyle = style
        switch segment {
        case .paragraph(let text):
            return AnyView(markdownInlineFlow(text, font: originalStyle.bodyFont, color: colorOverride ?? originalStyle.textColor)
                .lineSpacing(4)
                .padding(.bottom, 8))
        default:
            return render(segment)
        }
    }

    @ViewBuilder
    private func markdownInlineText(
        _ text: String,
        font: Font,
        color: Color
    ) -> some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .tint(style.linkColor)
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }

    private func highlightedCode(_ code: String, language: String?) -> AttributedString {
        var attributed = codeSyntaxHighlighter.highlight(code, language)
        attributed.font = style.codeFont
        return attributed
    }

    private func markdownInlineFlow(_ text: String, font: Font, color: Color) -> some View {
        let inlines = MarkdownInlineParser.parse(text, softBreakMode: softBreakMode)
        let containsImage = inlines.containsInlineImage

        return Group {
            if containsImage {
                MarkdownInlineFlowLayout(spacing: 0, lineSpacing: 4) {
                    inlineRuns(
                        flattenedInlineRuns(inlines, splitForLayout: true),
                        font: font,
                        color: color
                    )
                }
            } else {
                Text(inlineAttributedString(
                    flattenedInlineRuns(inlines, splitForLayout: false),
                    font: font,
                    color: color
                ))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .tint(style.linkColor)
        .textSelection(.enabled)
    }

    private func inlineRuns(_ runs: [MarkdownInlineRun], font: Font, color: Color) -> some View {
        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
            inlineRun(run, font: font, color: color)
        }
    }

    private func inlineRun(_ run: MarkdownInlineRun, font: Font, color: Color) -> AnyView {
        switch run.content {
        case .text(let text):
            let textView = Text(text)
                .font(run.resolvedFont(base: font))
                .foregroundStyle(run.linkDestination == nil ? color : style.linkColor)
                .strikethrough(run.isStrikethrough, color: run.linkDestination == nil ? color : style.linkColor)
                .underline(run.linkDestination != nil)

            if let destination = run.linkDestination,
               let url = resolvedURL(destination, relativeTo: baseURL) {
                return AnyView(Link(destination: url) { textView })
            }

            return AnyView(textView)

        case .softBreak:
            return AnyView(Text(" ").font(font))

        case .lineBreak:
            return AnyView(Color.clear
                .frame(width: 0, height: 0)
                .layoutValue(key: MarkdownInlineLineBreakKey.self, value: true))

        case .code(let code):
            return AnyView(Text(code)
                .font(style.codeFont)
                .foregroundStyle(style.codeForegroundColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(style.codeBackgroundColor)
                ))

        case .image(let alt, let source):
            return AnyView(inlineImage(alt: alt, source: source))
        }
    }

    private func splitTextForWrapping(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""

        for character in text {
            if character.isCJKLike {
                if current.isEmpty == false {
                    result.append(current)
                    current = ""
                }
                result.append(String(character))
                continue
            }

            current.append(character)
            if character.isWhitespace || current.count >= 18 {
                result.append(current)
                current = ""
            }
        }
        if current.isEmpty == false {
            result.append(current)
        }
        return result.isEmpty ? [text] : result
    }

    private func flattenedInlineRuns(_ inlines: [MarkdownSegment.Inline], splitForLayout: Bool) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        appendInlineRuns(inlines, attributes: MarkdownInlineAttributes(), splitForLayout: splitForLayout, into: &runs)
        return runs
    }

    private func appendInlineRuns(
        _ inlines: [MarkdownSegment.Inline],
        attributes: MarkdownInlineAttributes,
        splitForLayout: Bool,
        into runs: inout [MarkdownInlineRun]
    ) {
        for inline in inlines {
            appendInlineRun(inline, attributes: attributes, splitForLayout: splitForLayout, into: &runs)
        }
    }

    private func appendInlineRun(
        _ inline: MarkdownSegment.Inline,
        attributes: MarkdownInlineAttributes,
        splitForLayout: Bool,
        into runs: inout [MarkdownInlineRun]
    ) {
        switch inline {
        case .text(let text):
            let decoded = text.decodingHTMLEntities()
            let parts = splitForLayout ? splitTextForWrapping(decoded) : [decoded]
            for part in parts where part.isEmpty == false {
                runs.append(MarkdownInlineRun(content: .text(part), attributes: attributes))
            }

        case .softBreak:
            runs.append(MarkdownInlineRun(content: .softBreak, attributes: attributes))

        case .lineBreak:
            runs.append(MarkdownInlineRun(content: .lineBreak, attributes: attributes))

        case .code(let code):
            runs.append(MarkdownInlineRun(content: .code(code.decodingHTMLEntities()), attributes: attributes))

        case .emphasis(let children):
            var childAttributes = attributes
            childAttributes.isEmphasis = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .strong(let children):
            var childAttributes = attributes
            childAttributes.isStrong = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .strikethrough(let children):
            var childAttributes = attributes
            childAttributes.isStrikethrough = true
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .link(let children, let destination):
            var childAttributes = attributes
            childAttributes.linkDestination = destination
            appendInlineRuns(children, attributes: childAttributes, splitForLayout: splitForLayout, into: &runs)

        case .image(let alt, let source):
            runs.append(MarkdownInlineRun(content: .image(alt: alt, source: source), attributes: attributes))

        case .html(let html):
            if html.isHTMLLineBreak {
                runs.append(MarkdownInlineRun(content: .lineBreak, attributes: attributes))
            } else {
                let text = html.strippingHTMLTags().decodingHTMLEntities()
                guard text.isEmpty == false else { return }
                let parts = splitForLayout ? splitTextForWrapping(text) : [text]
                for part in parts where part.isEmpty == false {
                    runs.append(MarkdownInlineRun(content: .text(part), attributes: attributes))
                }
            }
        }
    }

    private func inlineAttributedString(_ runs: [MarkdownInlineRun], font: Font, color: Color) -> AttributedString {
        var result = AttributedString()

        for run in runs {
            switch run.content {
            case .text(let text):
                result += attributedInlineText(text, run: run, font: font, color: color)

            case .softBreak:
                result += AttributedString(" ")

            case .lineBreak:
                result += AttributedString("\n")

            case .code(let code):
                var attributed = AttributedString(code)
                attributed.font = style.codeFont
                attributed.foregroundColor = style.codeForegroundColor
                attributed.backgroundColor = style.codeBackgroundColor
                result += attributed

            case .image(let alt, _):
                result += attributedInlineText(alt.isEmpty ? "Image" : alt, run: run, font: font, color: style.secondaryTextColor)
            }
        }

        return result
    }

    private func attributedInlineText(_ text: String, run: MarkdownInlineRun, font: Font, color: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = run.resolvedFont(base: font)
        attributed.foregroundColor = run.linkDestination == nil ? color : style.linkColor

        if run.isStrikethrough {
            attributed.strikethroughStyle = .single
        }

        if let destination = run.linkDestination {
            attributed.underlineStyle = .single
            attributed.link = resolvedURL(destination, relativeTo: baseURL)
        }

        return attributed
    }

    @ViewBuilder
    private func inlineImage(alt: String, source: String) -> some View {
        if let url = resolvedURL(source, relativeTo: imageBaseURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                case .failure:
                    Text(alt.isEmpty ? "Image" : alt)
                        .font(.caption)
                        .foregroundStyle(style.secondaryTextColor)
                case .empty:
                    ProgressView()
                        .controlSize(.mini)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            Text(alt.isEmpty ? "Image" : alt)
                .font(.caption)
                .foregroundStyle(style.secondaryTextColor)
        }
    }

    @ViewBuilder
    private func markdownImage(alt: String, source: String) -> some View {
        if let url = resolvedURL(source, relativeTo: imageBaseURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .failure:
                    imageFallback(alt: alt)
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 96)
                @unknown default:
                    imageFallback(alt: alt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        } else {
            imageFallback(alt: alt)
                .padding(.bottom, 8)
        }
    }

    private func imageFallback(alt: String) -> some View {
        Text(alt.isEmpty ? "Image" : alt)
            .font(.caption)
            .foregroundStyle(style.secondaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(style.tableBorderColor, lineWidth: 1)
            )
    }

    private func resolvedURL(_ source: String, relativeTo baseURL: URL?) -> URL? {
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        return URL(string: source, relativeTo: baseURL ?? self.baseURL)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(.title, design: .default).weight(.semibold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        case 4: return .headline.weight(.semibold)
        case 5: return .subheadline.weight(.semibold)
        default: return .subheadline.weight(.semibold)
        }
    }

    private func bulletMarker(for level: Int) -> String {
        switch level % 3 {
        case 1: return "◦"
        case 2: return "▪"
        default: return "•"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == MarkdownSegment.Inline {
    var containsInlineImage: Bool {
        contains { inline in
            switch inline {
            case .image:
                return true
            case .emphasis(let children),
                 .strong(let children),
                 .strikethrough(let children),
                 .link(let children, _):
                return children.containsInlineImage
            default:
                return false
            }
        }
    }
}

private struct MarkdownInlineFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? fallbackWidth
        return layout(subviews: subviews, maxWidth: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, items: [(index: Int, origin: CGPoint, size: CGSize)]) {
        var items: [(Int, CGPoint, CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        let availableWidth = max(maxWidth, 1)

        for index in subviews.indices {
            if subviews[index][MarkdownInlineLineBreakKey.self] {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                continue
            }

            let size = subviews[index].sizeThatFits(.unspecified)
            let shouldWrap = x > 0 && x + size.width > availableWidth
            if shouldWrap {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            items.append((index, CGPoint(x: x, y: y), size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x)
        }

        return (CGSize(width: min(usedWidth, availableWidth), height: y + lineHeight), items)
    }

    private var fallbackWidth: CGFloat {
        #if canImport(UIKit)
        max(220, UIScreen.main.bounds.width - 88)
        #else
        320
        #endif
    }
}

private struct MarkdownInlineLineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

private struct MarkdownInlineAttributes: Equatable {
    var isEmphasis = false
    var isStrong = false
    var isStrikethrough = false
    var linkDestination: String?
}

private struct MarkdownInlineRun: Equatable {
    enum Content: Equatable {
        case text(String)
        case softBreak
        case lineBreak
        case code(String)
        case image(alt: String, source: String)
    }

    let content: Content
    let attributes: MarkdownInlineAttributes

    var isStrikethrough: Bool {
        attributes.isStrikethrough
    }

    var linkDestination: String? {
        attributes.linkDestination
    }

    func resolvedFont(base: Font) -> Font {
        var font = base
        if attributes.isStrong {
            font = font.weight(.semibold)
        }
        if attributes.isEmphasis {
            font = font.italic()
        }
        return font
    }
}

private extension String {
    func strippingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    func decodingHTMLEntities() -> String {
        var decoded = self
        let replacements = [
            "&lt;": "<",
            "&gt;": ">",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, value) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }

        return decoded.decodingNumericHTMLEntities()
    }

    func decodingNumericHTMLEntities() -> String {
        let pattern = "&#([0-9]+);|&#x([0-9A-Fa-f]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

        let nsRange = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: nsRange).reversed()
        var result = self

        for match in matches {
            guard let matchRange = Range(match.range(at: 0), in: result) else { continue }

            let decimalRange = Range(match.range(at: 1), in: result)
            let hexRange = Range(match.range(at: 2), in: result)
            let value: UInt32?

            if let decimalRange {
                value = UInt32(result[decimalRange], radix: 10)
            } else if let hexRange {
                value = UInt32(result[hexRange], radix: 16)
            } else {
                value = nil
            }

            guard let value, let scalar = UnicodeScalar(value) else { continue }
            result.replaceSubrange(matchRange, with: String(Character(scalar)))
        }

        return result
    }

    var isHTMLLineBreak: Bool {
        range(of: "^<\\s*br\\s*/?\\s*>$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private extension Character {
    var isCJKLike: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2EFF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}
