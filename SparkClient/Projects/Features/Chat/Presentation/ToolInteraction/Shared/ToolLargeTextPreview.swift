import SwiftUI
import UIKit

struct ToolLargeTextDisplay {
    let fullText: String
    let displayText: String
    let isTruncated: Bool
    let fullCharacterCount: Int
    let visibleCharacterCount: Int

    init(text: String, emptyPlaceholder: String, limit: Int) {
        fullText = text
        fullCharacterCount = text.count
        isTruncated = text.count > limit
        visibleCharacterCount = isTruncated ? limit : text.count

        if text.isEmpty {
            displayText = emptyPlaceholder
        } else if isTruncated {
            displayText = String(text.prefix(limit))
        } else {
            displayText = text
        }
    }
}

enum ToolLargeTextChunkBuilder {
    static func chunks(from text: String, maxLineLength: Int = 800) -> [String] {
        guard text.isEmpty == false else { return [""] }

        var result: [String] = []
        var currentLine = ""
        for character in text {
            if character == "\n" {
                if currentLine.isEmpty == false {
                    result.append(contentsOf: splitLongLine(currentLine, maxLineLength: maxLineLength))
                } else {
                    result.append("")
                }
                currentLine = ""
            } else {
                currentLine.append(character)
            }
        }
        if currentLine.isEmpty == false {
            result.append(contentsOf: splitLongLine(currentLine, maxLineLength: maxLineLength))
        }
        return result.isEmpty ? [text] : result
    }

    private static func splitLongLine(_ line: String, maxLineLength: Int) -> [String] {
        guard line.count > maxLineLength else { return [line] }
        var chunks: [String] = []
        var start = line.startIndex
        while start < line.endIndex {
            let end = line.index(start, offsetBy: maxLineLength, limitedBy: line.endIndex) ?? line.endIndex
            chunks.append(String(line[start..<end]))
            start = end
        }
        return chunks
    }
}

struct ToolLargeTextPreview: View {
    let display: ToolLargeTextDisplay
    @State private var didCopyFullText = false

    private var usesScrollMode: Bool {
        let text = display.displayText
        let lineCount = text.components(separatedBy: "\n").count
        return text.count > 1_200 || lineCount > 24
    }

    private var textChunks: [String] {
        ToolLargeTextChunkBuilder.chunks(from: display.displayText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewContent(
                maxHeight: ToolSheetDisplayLimits.responsiveMaxPreviewHeight(for: UIScreen.main.bounds.height)
            )

            if display.isTruncated {
                truncationFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func previewContent(maxHeight: CGFloat) -> some View {
        if usesScrollMode {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(textChunks.enumerated()), id: \.offset) { _, chunk in
                        Text(chunk)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: maxHeight)
        } else {
            Text(display.displayText)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var truncationFooter: some View {
        HStack(spacing: 10) {
            Label(
                String(
                    format: L10n.text(
                        "chat.tool_preview.truncated_count",
                        fallback: "仅显示前 %d / %d 个字符"
                    ),
                    display.visibleCharacterCount,
                    display.fullCharacterCount
                ),
                systemImage: "scissors"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                UIPasteboard.general.string = display.fullText
                didCopyFullText = true
            } label: {
                Label(
                    didCopyFullText
                        ? L10n.text("common.copied", fallback: "已复制")
                        : L10n.text("common.copy_all", fallback: "复制全部"),
                    systemImage: didCopyFullText ? "checkmark" : "doc.on.doc"
                )
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .disabled(display.fullText.isEmpty)
        }
    }
}
