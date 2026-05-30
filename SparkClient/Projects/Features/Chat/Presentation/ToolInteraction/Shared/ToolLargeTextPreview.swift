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

struct ToolLargeTextPreview: View {
    let display: ToolLargeTextDisplay
    @State private var didCopyFullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.displayText)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if display.isTruncated {
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
    }
}
