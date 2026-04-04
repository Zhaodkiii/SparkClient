import SwiftUI

struct MarkdownDocumentStyle: Sendable {
    let textColor: Color
    let secondaryTextColor: Color
    let headingColor: Color
    let linkColor: Color
    let codeBackgroundColor: Color
    let quoteBarColor: Color
    let quoteBackgroundColor: Color
    let tableBorderColor: Color
    let tableHeaderBackgroundColor: Color
    let paragraphSpacing: CGFloat
    let blockSpacing: CGFloat

    static let documentation = MarkdownDocumentStyle(
        textColor: .primary,
        secondaryTextColor: .secondary,
        headingColor: .primary,
        linkColor: .accentColor,
        codeBackgroundColor: Color.primary.opacity(0.08),
        quoteBarColor: .accentColor,
        quoteBackgroundColor: Color.accentColor.opacity(0.08),
        tableBorderColor: Color.secondary.opacity(0.25),
        tableHeaderBackgroundColor: Color.secondary.opacity(0.12),
        paragraphSpacing: 8,
        blockSpacing: 10
    )

    static func chatBubble(textColor: Color) -> MarkdownDocumentStyle {
        MarkdownDocumentStyle(
            textColor: textColor,
            secondaryTextColor: textColor.opacity(0.78),
            headingColor: textColor,
            linkColor: textColor,
            codeBackgroundColor: textColor.opacity(0.12),
            quoteBarColor: textColor.opacity(0.75),
            quoteBackgroundColor: textColor.opacity(0.08),
            tableBorderColor: textColor.opacity(0.3),
            tableHeaderBackgroundColor: textColor.opacity(0.12),
            paragraphSpacing: 6,
            blockSpacing: 8
        )
    }
}

struct MarkdownDocumentView: View {
    private let segments: [MarkdownSegment]
    private let style: MarkdownDocumentStyle

    init(text: String, style: MarkdownDocumentStyle = .documentation) {
        self.segments = MarkdownSegmentParser.parse(text)
        self.style = style
    }

    init(segments: [MarkdownSegment], style: MarkdownDocumentStyle = .documentation) {
        self.segments = segments
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                render(segment)
            }
        }
    }

    @ViewBuilder
    private func render(_ segment: MarkdownSegment) -> some View {
        switch segment {
        case .heading(let level, let text):
            markdownInlineText(text, font: headingFont(level: level), color: style.headingColor)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let text):
            markdownInlineText(text, font: .body, color: style.textColor)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(style.textColor)
                            .padding(.top, 1)
                        markdownInlineText(item, font: .body, color: style.textColor)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(style.textColor)
                            .padding(.top, 1)
                        markdownInlineText(item, font: .body, color: style.textColor)
                    }
                }
            }

        case .taskList(let items):
            VStack(alignment: .leading, spacing: style.paragraphSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isDone ? style.linkColor : style.secondaryTextColor)
                            .padding(.top, 2)
                        markdownInlineText(item.text, font: .body, color: style.textColor)
                    }
                }
            }

        case .blockquote(let lines):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.quoteBarColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        markdownInlineText(line, font: .body, color: style.secondaryTextColor)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.quoteBackgroundColor)
            )

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, language.isEmpty == false {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style.secondaryTextColor)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(style.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.codeBackgroundColor)
            )

        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    tableRow(cells: header, isHeader: true)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        tableRow(cells: row, isHeader: false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(style.tableBorderColor, lineWidth: 1)
                )
            }

        case .thematicBreak:
            Divider()
                .overlay(style.tableBorderColor)
                .padding(.vertical, 2)
        }
    }

    private func tableRow(cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                markdownInlineText(
                    cell,
                    font: isHeader ? .subheadline.weight(.semibold) : .subheadline,
                    color: style.textColor
                )
                .frame(minWidth: 120, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(style.tableBorderColor)
                        .frame(width: 1)
                }
            }
        }
        .background(isHeader ? style.tableHeaderBackgroundColor : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.tableBorderColor)
                .frame(height: 1)
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

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline.weight(.semibold)
        case 4: return .subheadline.weight(.semibold)
        default: return .subheadline.weight(.medium)
        }
    }
}
