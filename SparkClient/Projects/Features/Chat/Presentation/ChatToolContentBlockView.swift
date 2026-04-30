import SwiftUI

/// 助手消息中的「工具输出」入口块：点击后在全局 Sheet 中查看详情与关联卡片。
struct ChatToolContentBlockView: View {
    /// 工具名称
    let toolName: String
    /// 工具返回的内容文本
    let toolContent: String
    /// 是否处于流式加载中
    let isStreaming: Bool
    /// 点击后在全局 Sheet 展示工具详情
    let onOpenDetail: () -> Void

    var body: some View {
        ToolDetailOpenButton(
            title: L10n.text("chat.bubble.tool.title"),
            subtitle: toolName,
            isStreaming: isStreaming,
            action: onOpenDetail
        )
        .padding(.leading, 5)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}

/// 工具执行中状态展示块（对齐 AI_HLY loadingSection）
/// 视觉效果：
/// - 标题：渐变扫光动画，表示正在执行
/// - 描述区：只展示最新 3 行日志，带透明度、模糊、渐变动画
struct ChatOperationalStatusBlockView: View {
    /// 执行状态标题（如：获取健康数据中...）
    let operationalState: String
    /// 执行过程描述（流式日志/进度文本）
    let operationalDescription: String

    var body: some View {
        HStack(alignment: .top) {
            if operationalState.isEmpty == false {
                VStack(alignment: .leading) {
                    // 渐变动画标题
                    LoadingGradientText(text: operationalState)
                        .padding(5)

                    if operationalDescription.isEmpty == false {
                        // 只取最后 3 行日志展示（保持界面简洁）
                        let allLines = operationalDescription
                            .split(separator: "\n", omittingEmptySubsequences: false)
                            .map(String.init)
                        let displayLines = Array(allLines.suffix(3))

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    // 字号逐级变大（最新一行最大）
                                    .font(.system(size: idx == 2 ? 10 : (idx == 1 ? 9 : 8)))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    // 最新一行使用主题色
                                    .foregroundStyle(idx == 2 ? Color.accentColor : Color.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    // 旧日志透明度更低、带模糊
                                    .opacity(idx == 0 ? 0.4 : idx == 1 ? 0.7 : 1.0)
                                    .blur(radius: idx == 0 ? 1 : 0)
                                    .padding(.horizontal, 5)
                                    // 插入/移除动画：新行从下往上出现，旧行从上移除
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        )
                                    )
                            }
                        }
                        .padding(.bottom, 5)
                        // 日志更新时的弹性动画
                        .animation(
                            .spring(response: 0.8, dampingFraction: 0.8, blendDuration: 0.6),
                            value: operationalDescription
                        )
                    }
                }
            } else {
                // 无状态文本时，显示图标占位
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .overlay(
            // 圆角边框
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(20)
        .animation(.spring(response: 0.8, dampingFraction: 0.95), value: operationalDescription)
    }
}

/// 加载中渐变扫光文字（执行状态专用）
/// 效果：渐变色从左到右循环移动，模拟加载中高亮动画
private struct LoadingGradientText: View {
    let text: String
    @State private var animate = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.clear)
            .overlay(
                // 渐变层来回移动实现扫光效果
                LinearGradient(
                    colors: [Color.secondary, Color.accentColor, Color.secondary],
                    startPoint: animate ? .leading : .trailing,
                    endPoint: animate ? .trailing : .leading
                )
            )
            // 用文字作为遮罩，只在文字区域显示渐变
            .mask(
                Text(text)
                    .font(.subheadline.weight(.medium))
            )
            .onAppear {
                // 无限循环动画：1.2s 往复
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    animate.toggle()
                }
            }
    }
}

/// 打开工具详情 Sheet 的按钮（标题 + 工具名 + 预览图标）
private struct ToolDetailOpenButton: View {
    let title: String
    let subtitle: String
    let isStreaming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
    }
}
