import SwiftUI

struct DeepTutorAssistantResponseView: View {
    let message: DeepTutorMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(renderSegments) { segment in
                switch segment {
                case .thinking(let text):
                    DeepTutorThinkingCardView(text: text)
                case .markdown(let text):
                    DeepTutorMarkdownRenderer(markdown: text)
                }
            }
        }
    }

    private var renderSegments: [Segment] {
        var segments: [Segment] = []
        for block in message.blocks where block.kind != .envelope {
            switch block.payload {
            case .thinking(let text) where text.isEmpty == false:
                segments.append(.thinking(text))
            case .text(let text) where text.isEmpty == false:
                segments.append(.markdown(text))
            default:
                continue
            }
        }
        if segments.isEmpty, message.content.isEmpty == false {
            segments.append(.markdown(message.content))
        }
        return segments
    }

    private enum Segment: Identifiable {
        case thinking(String)
        case markdown(String)

        var id: String {
            switch self {
            case .thinking(let text): return "thinking-\(text.hashValue)"
            case .markdown(let text): return "markdown-\(text.hashValue)"
            }
        }
    }
}
