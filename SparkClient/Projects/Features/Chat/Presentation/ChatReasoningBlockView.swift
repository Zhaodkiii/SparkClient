import SwiftUI

/// Collapsible assistant reasoning / chain-of-thought block (above the final answer).
struct ChatReasoningBlockView: View {
    let text: String
    let timeText: String?
    let isStreaming: Bool
    let isLastAssistantMessage: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading) {
            ToggleButton(
                title: L10n.text("chat.bubble.reasoning.title"),
                timeText: timeText ?? "",
                isExpanded: $expanded
            )

            if expanded {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .scale))
                    .textSelection(.enabled)
                    .padding(.bottom, 5)
            } else if isStreaming && isLastAssistantMessage {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayReasoningLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: idx == 2 ? 10 : (idx == 1 ? 9 : 8)))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(idx == 2 ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(idx == 0 ? 0.4 : idx == 1 ? 0.7 : 1.0)
                            .blur(radius: idx == 0 ? 1 : 0)
                            .padding(.horizontal, 5)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                    }
                }
                .padding(.bottom, 5)
                .animation(
                    .spring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.5),
                    value: displayReasoningLines
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 5)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private var displayReasoningLines: [String] {
        // 与 AI_HLY 保持一致：折叠时固定展示最近 3 条，不足 3 条前补空行用于视觉层次。
        let raw = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let last3 = Array(raw.suffix(3))
        if last3.isEmpty { return [] }
        if last3.count < 3 {
            return Array(repeating: " ", count: 3 - last3.count) + last3
        }
        return last3
    }
}

private struct ToggleButton: View {
    let title: String
    let timeText: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if timeText.isEmpty == false {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
