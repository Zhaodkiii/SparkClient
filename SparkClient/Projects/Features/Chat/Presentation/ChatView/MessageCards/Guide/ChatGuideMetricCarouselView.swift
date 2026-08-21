import SwiftUI

/// 引导卡片数据滑块：横向分页切换四类健康数据 section，底部胶囊/圆点指示当前位置。
/// 注入 `homeDestinationBuilder` 后滑块页主体可点击，通过消息内 NavigationLink push 健康首页
/// 并按类别定位分段（CHAT-000025）；builder 缺失时降级为纯展示面板。
struct ChatGuideMetricCarouselView: View {
    let sections: [ChatGuideMetricSection]
    var homeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    @State private var selectedIndex: Int = 0

    private var displayIndex: Int {
        guard sections.isEmpty == false else { return 0 }
        return min(max(0, selectedIndex), sections.count - 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            if sections.isEmpty {
                ChatGuideMetricEmptyStateView(
                    title: L10n.text("chat.guide.carousel.empty.title", fallback: "暂无健康数据")
                )
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { _, section in
                        sectionPage(section)
                            .tag(sections.firstIndex(where: { $0.id == section.id }) ?? 0)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 156)
                .fixedSize(horizontal: false, vertical: true)

                ChatGuidePageIndicator(count: sections.count, currentIndex: displayIndex)
            }
        }
    }

    /// 单个滑块页：有 destination builder 时整页包 NavigationLink（点击范围不含科普问题列表）。
    @ViewBuilder
    private func sectionPage(_ section: ChatGuideMetricSection) -> some View {
        if let homeDestinationBuilder {
            NavigationLink {
                homeDestinationBuilder(section.category)
            } label: {
                ChatGuideMetricSectionView(section: section)
            }
            .buttonStyle(.plain)
        } else {
            ChatGuideMetricSectionView(section: section)
        }
    }
}

/// 分页指示器：选中项为短胶囊条，未选中为小圆点；颜色跟随 `Color.primary` 自适应深浅模式。
private struct ChatGuidePageIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                if index == currentIndex {
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: 16, height: 6)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
        .accessibilityHidden(true)
    }
}

/// 单个数据 section 面板：内嵌卡片（`secondarySystemGroupedBackground`），
/// 右上角可放置"去绑定"按钮，底部为柱状图。
private struct ChatGuideMetricSectionView: View {
    let section: ChatGuideMetricSection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(section.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let subtitle = section.subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let action = section.action {
                ChatGuideActionButton(action: action)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.state {
        case .ready, .partial:
            if section.items.isEmpty {
                ChatGuideMetricEmptyStateView(
                    title: L10n.text("chat.guide.section.state.empty", fallback: "暂无数据")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    metricItemsRow
                    if let chart = section.chart {
                        ChatGuideBarChartView(chart: chart, tint: chartTint)
                            .frame(height: 32)
                    }
                }
            }
        case .unauthorized:
            ChatGuideMetricEmptyStateView(
                title: L10n.text("chat.guide.section.state.unauthorized", fallback: "未授权健康数据"),
                actionTitle: nil
            )
        case .empty:
            ChatGuideMetricEmptyStateView(
                title: L10n.text("chat.guide.section.state.empty", fallback: "暂无数据")
            )
        case .failed:
            ChatGuideMetricEmptyStateView(
                title: L10n.text("chat.guide.section.state.failed", fallback: "数据加载失败")
            )
        case .unavailable:
            ChatGuideMetricEmptyStateView(
                title: L10n.text("chat.guide.section.state.unavailable", fallback: "健康数据不可用")
            )
        }
    }

    /// 指标行：常规字号横排（基线对齐），辅助功能大字号时自动切为竖排，避免文字挤压。
    private var metricItemsRow: some View {
        AnyLayout(itemsLayout) {
            ForEach(section.items) { item in
                ChatGuideMetricItemView(item: item)
            }
            Spacer(minLength: 0)
        }
    }

    private var itemsLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        } else {
            AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 16))
        }
    }

    /// 柱状图着色跟随 section 首个指标 tint（如步数绿、体重蓝），保持卡片内色彩语言统一。
    private var chartTint: Color {
        section.items.first.map { ChatGuideMetricColor.color(for: $0.tintName) } ?? .accentColor
    }

    private var accessibilitySummary: String {
        var parts = [section.title]
        if let subtitle = section.subtitle, subtitle.isEmpty == false {
            parts.append(subtitle)
        }
        for item in section.items {
            var line = "\(item.title) \(item.valueText)"
            if let unit = item.unitText {
                line += " \(unit)"
            }
            parts.append(line)
        }
        return parts.joined(separator: ", ")
    }
}

/// 右上角"去绑定"胶囊按钮。
private struct ChatGuideActionButton: View {
    let action: ChatGuideMetricAction

    var body: some View {
        Button(action: {}) {
            Text(action.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(false)
    }
}

/// 单个指标（左侧彩色竖条 + 灰色标题 + 大数字 + 单位）。
/// 大数字使用 `.title` 语义字号 + rounded 重字重，随 Dynamic Type 缩放并保持等宽对齐。
private struct ChatGuideMetricItemView: View {
    let item: ChatGuideMetricItem

    /// 彩色竖条高度随字号缩放，保证辅助功能大字号下与数字的比例协调。
    @ScaledMetric(relativeTo: .title) private var accentBarHeight: CGFloat = 20

    private var accentColor: Color {
        ChatGuideMetricColor.color(for: item.tintName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor)
                .frame(width: 4, height: accentBarHeight)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(item.valueText)
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = item.unitText, unit.isEmpty == false {
                        Text(unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)，\(item.valueText)\(item.unitText.map { " \($0)" } ?? "")")
    }
}

/// 颜色主题映射：按指标 tintName 返回系统语义色（自动适配深浅模式）。
private enum ChatGuideMetricColor {
    static func color(for name: String) -> Color {
        switch name {
        case "green": return Color(uiColor: .systemGreen)
        case "orange": return Color(uiColor: .systemOrange)
        case "blue": return Color(uiColor: .systemBlue)
        case "red": return Color(uiColor: .systemRed)
        case "purple": return Color(uiColor: .systemPurple)
        case "accent": return .accentColor
        default: return .accentColor
        }
    }
}

/// 迷你柱状图：归一化值序列的垂直圆角柱，底部虚线基准线（`.separator` 自适应深浅模式）。
private struct ChatGuideBarChartView: View {
    let chart: ChatGuideMiniChart
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let bars = normalizedBars(in: proxy.size)
            let baselineY = proxy.size.height - 1
            ZStack(alignment: .bottom) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baselineY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: baselineY))
                }
                .stroke(
                    Color(uiColor: .separator),
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                )

                HStack(alignment: .bottom, spacing: barSpacing(for: bars.count, totalWidth: proxy.size.width)) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint.opacity(0.85))
                            .frame(width: barWidth(for: bars.count, totalWidth: proxy.size.width), height: bar.height)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private struct Bar {
        let height: CGFloat
    }

    private func normalizedBars(in size: CGSize) -> [Bar] {
        guard size.height > 4 else { return [] }
        let maxBarHeight = size.height - 4
        return chart.normalizedValues.map { value in
            let clamped = min(max(value, 0.05), 1)
            return Bar(height: CGFloat(clamped) * maxBarHeight)
        }
    }

    private func barSpacing(for count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let bw = barWidth(for: count, totalWidth: totalWidth)
        let totalBars = CGFloat(count) * bw
        let remaining = max(0, totalWidth - totalBars)
        return count > 1 ? remaining / CGFloat(count - 1) : 0
    }

    private func barWidth(for count: Int, totalWidth: CGFloat) -> CGFloat {
        let ideal = totalWidth / CGFloat(max(count, 1)) * 0.55
        return min(ideal, 10)
    }
}

/// section 空态/未授权/失败态统一轻量面板（SF Symbol + hierarchical 渲染 + 文字）。
private struct ChatGuideMetricEmptyStateView: View {
    let title: String
    var actionTitle: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

#Preview("数据滑块-Light") {
    ChatGuideMetricCarouselView(
        sections: ChatGuideCardPreviewFixtures.fullPayload.metricSections
    )
    .padding()
}

#Preview("数据滑块-Dark") {
    ChatGuideMetricCarouselView(
        sections: ChatGuideCardPreviewFixtures.fullPayload.metricSections
    )
    .padding()
    .preferredColorScheme(.dark)
}
