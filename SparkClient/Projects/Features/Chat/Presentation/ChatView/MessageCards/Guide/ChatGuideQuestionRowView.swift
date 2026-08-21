import SwiftUI

/// 引导卡片科普问题行：独立圆角卡片，左侧蓝色 # 图标（SF Symbol `number`），右侧 chevron 箭头。
/// 点击后直接走当前会话发送链路，不弹二次确认；发送中置灰防重入。
/// 点击触发轻触觉反馈，按压缩放 + 弹簧回弹，卡片底色用语义色自适应深浅模式。
struct ChatGuideQuestionRowView: View {
    let question: ChatGuideQuestion
    let isDisabled: Bool
    let onTap: () -> Void

    /// 图标圆径随字号缩放，辅助功能大字号下与标题保持比例协调。
    @ScaledMetric(relativeTo: .title3) private var iconDiameter: CGFloat = 30

    init(
        question: ChatGuideQuestion,
        isDisabled: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.question = question
        self.isDisabled = isDisabled
        self.onTap = onTap
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .systemBlue),
                                    Color(uiColor: .systemBlue).opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: iconDiameter, height: iconDiameter)
                    Image(systemName: "number")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Text(question.title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(ChatGuideQuestionButtonStyle())
        .disabled(isDisabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(question.title)
        .accessibilityHint(L10n.text("chat.guide.question.accessibility.hint", fallback: "发送该健康科普问题"))
    }

    private func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }
}

/// 按压反馈：轻点时卡片微缩至 0.98，松手以弹簧动画回弹。
private struct ChatGuideQuestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("问题行-Light") {
    VStack(spacing: 12) {
        ChatGuideQuestionRowView(
            question: ChatGuideCardPreviewFixtures.fullPayload.questions[0],
            onTap: {}
        )
        ChatGuideQuestionRowView(
            question: ChatGuideCardPreviewFixtures.fullPayload.questions[1],
            isDisabled: true,
            onTap: {}
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("问题行-Dark") {
    VStack(spacing: 12) {
        ChatGuideQuestionRowView(
            question: ChatGuideCardPreviewFixtures.fullPayload.questions[0],
            onTap: {}
        )
        ChatGuideQuestionRowView(
            question: ChatGuideCardPreviewFixtures.fullPayload.questions[1],
            isDisabled: true,
            onTap: {}
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
    .preferredColorScheme(.dark)
}
