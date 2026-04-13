import SwiftUI

/// 助手消息中的“工具输出内容”折叠块（对齐 AI_HLY 的 toolContentView）。
/// - 头部：标题 + 工具名 + 展开收起箭头
/// - 内容：仅在展开时显示，支持文本选择，便于复制调试
struct ChatToolContentBlockView: View {
    let toolName: String
    let toolContent: String
    let isStreaming: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading) {
            ToggleButton(
                title: L10n.text("chat.bubble.tool.title"),
                timeText: toolName,
                isExpanded: $expanded
            )

            if expanded {
                // 工具返回内容通常是多行日志/结果文本，这里保持较小字号并开启选择。
                Text(toolContent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .scale))
                    .textSelection(.enabled)
                    .padding(.bottom, 5)
            }
        }
        .padding(.leading, 5)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}

/// 与 AI_HLY `loadingSection()` 对齐的工具执行中状态块：
/// - 标题使用渐变高亮文本
/// - 描述区展示最近三行，带层级透明度/模糊/过渡动画
struct ChatOperationalStatusBlockView: View {
    let operationalState: String
    let operationalDescription: String

    var body: some View {
        HStack(alignment: .top) {
            if operationalState.isEmpty == false {
                VStack(alignment: .leading) {
                    LoadingGradientText(text: operationalState)
                        .padding(5)

                    if operationalDescription.isEmpty == false {
                        // 与 AI_HLY 一致：只显示最新三行“过程描述”用于流式反馈。
                        let allLines = operationalDescription
                            .split(separator: "\n", omittingEmptySubsequences: false)
                            .map(String.init)
                        let displayLines = Array(allLines.suffix(3))

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: idx == 2 ? 10 : (idx == 1 ? 9 : 8)))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
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
                            .spring(response: 0.8, dampingFraction: 0.8, blendDuration: 0.6),
                            value: operationalDescription
                        )
                    }
                }
            } else {
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(20)
        .animation(.spring(response: 0.8, dampingFraction: 0.95), value: operationalDescription)
    }
}

private struct LoadingGradientText: View {
    let text: String
    @State private var animate = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.clear)
            .overlay(
                // 渐变来回移动，模拟“执行中”高亮扫光效果。
                LinearGradient(
                    colors: [Color.secondary, Color.accentColor, Color.secondary],
                    startPoint: animate ? .leading : .trailing,
                    endPoint: animate ? .trailing : .leading
                )
            )
            .mask(
                Text(text)
                    .font(.subheadline.weight(.medium))
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    animate.toggle()
                }
            }
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
                        .lineLimit(1)
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
