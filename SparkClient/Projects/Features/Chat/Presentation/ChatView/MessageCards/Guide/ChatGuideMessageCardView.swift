import SwiftUI

/// 新会话首条系统引导卡片：
/// 上半部分为可横向切换的健康数据滑块，下半部分为固定健康科普问题列表。
/// 纯渲染组件：数据全部来自 payload，点击回调上抛，不直接拉取网络或写 DB。
///
/// 配色采用语义层级：外层容器 `systemGroupedBackground`，内嵌卡片
/// `secondarySystemGroupedBackground`，Light 模式下近似设计稿的浅灰底 + 纯白卡片，
/// Dark 模式下自动映射为黑底 + 深灰卡片，无需硬编码色值。
struct ChatGuideMessageCardView: View {
    let payload: ChatGuideCardPayload
    let onQuestionTap: (ChatGuideQuestion) -> Void

    /// 正在发送中的问题 id（用于按钮置灰防重入），由外部注入。
    var sendingQuestionIDs: Set<String> = []
    /// 滑块 → 健康首页 destination（CHAT-000025）；nil 时滑块降级为纯展示面板。
    var homeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    var body: some View {
        VStack(spacing: 16) {
            ChatGuideMetricCarouselView(
                sections: payload.metricSections,
                homeDestinationBuilder: homeDestinationBuilder
            )

            VStack(spacing: 12) {
                ForEach(payload.questions, id: \.id) { question in
                    ChatGuideQuestionRowView(
                        question: question,
                        isDisabled: sendingQuestionIDs.contains(question.id)
                    ) {
                        onQuestionTap(question)
                    }
                }
            }
        }
//        .padding(16)
//        .background(Color(uiColor: .systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("chat.guide.card.accessibility.label", fallback: "健康对话引导卡片"))
    }
}

#Preview("引导卡片-Light") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
}

#Preview("引导卡片-Dark") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
    .background(Color(uiColor: .systemBackground))
    .preferredColorScheme(.dark)
}

#Preview("引导卡片-辅助功能大字号") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("引导卡片-空数据") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.emptyPayload,
        onQuestionTap: { _ in }
    )
    .padding()
}
