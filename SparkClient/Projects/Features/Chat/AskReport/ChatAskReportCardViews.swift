import SwiftUI

// MARK: - 通用可选卡片组件
/// 带选中状态的通用可选卡片容器，支持自定义内部内容、点击事件与选中样式
struct ChatAskReportSelectableCard<Content: View>: View {
    /// 是否处于选中状态
    let isSelected: Bool
    /// 卡片点击回调
    let onTap: () -> Void
    /// 卡片内部自定义视图内容
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: onTap) {
            // 左侧选择图标 + 右侧内容 横向布局
            HStack(alignment: .top, spacing: 10) {
                // 选中/未选中圆形勾选图标
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    // 选中使用主题色，未选中使用次要文字色
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                // 自定义内容区域
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            // 卡片背景色
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            // 选中时显示主题色边框，未选中隐藏边框
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        // 去除按钮默认点击样式
        .buttonStyle(.plain)
    }
}

// MARK: - 病历主条目卡片
/// 病历分组主卡片，支持展开/收起、选中、展示子条目
struct ChatAskReportMedicalCaseCard: View {
    /// 数据源：健康档案条目模型
    let source: ChatSelectableHealthSource
    /// 当前条目是否选中
    let isSelected: Bool
    /// 子条目列表是否展开
    let isExpanded: Bool
    /// 搜索关键词（用于文字高亮）
    let searchQuery: String
    /// 已选中的子条目ID集合
    let selectedSourceIDs: Set<String>
    /// 当前病历卡片选中点击回调
    let onSelectCase: () -> Void
    /// 展开/收起子条目点击回调
    let onToggleExpand: () -> Void
    /// 子条目选中回调，参数为子条目唯一标识
    let onSelectChild: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 外层通用可选卡片，承载病历主体内容
            ChatAskReportSelectableCard(isSelected: isSelected, onTap: onSelectCase) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        // 标题、副标题、简介文本区域
                        VStack(alignment: .leading, spacing: 4) {
                            // 标题（关键词高亮）
                            highlightedText(source.title, query: searchQuery)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            // 副标题（非空时展示，关键词高亮）
                            if let subtitle = source.subtitle, subtitle.isEmpty == false {
                                highlightedText(subtitle, query: searchQuery)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            // 内容简介（非空时展示）
                            if let summary = source.summary, summary.isEmpty == false {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        // 存在子条目时，显示展开/收起箭头按钮
                        if source.children.isEmpty == false {
                            Button(action: onToggleExpand) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // 展示分类统计文本（检查报告、处方等数量）
                    if let related = ChatAskReportRelatedCountFormatter.format(source) {
                        Text(related)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // 资源类型标签（病历）
                    Text(L10n.text("chat.ask_report.resource_type.medical_case"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 展开状态且存在子条目时，渲染子条目列表
            if isExpanded, source.children.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(source.children) { child in
                        ChatAskReportChildRow(
                            source: child,
                            isSelected: selectedSourceIDs.contains(child.selectionKey),
                            searchQuery: searchQuery,
                            onTap: { onSelectChild(child.selectionKey) }
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

// MARK: - 病历子条目行视图
/// 病历分组下的子条目行（检查报告、处方等）
struct ChatAskReportChildRow: View {
    /// 子条目数据源
    let source: ChatSelectableHealthSource
    /// 是否选中
    let isSelected: Bool
    /// 搜索关键词
    let searchQuery: String
    /// 条目点击选中回调
    let onTap: () -> Void

    var body: some View {
        // 复用通用可选卡片，加载紧凑型内容视图
        ChatAskReportSelectableCard(isSelected: isSelected, onTap: onTap) {
            ChatAskReportLeafContent(source: source, searchQuery: searchQuery, compact: true)
        }
    }
}

// MARK: - 独立叶子节点卡片
/// 无下级节点的独立条目卡片（单独展示的档案项）
struct ChatAskReportLeafCard: View {
    /// 数据源
    let source: ChatSelectableHealthSource
    /// 是否选中
    let isSelected: Bool
    /// 搜索关键词
    let searchQuery: String
    /// 点击选中回调
    let onTap: () -> Void

    var body: some View {
        // 复用通用可选卡片，加载标准型内容视图
        ChatAskReportSelectableCard(isSelected: isSelected, onTap: onTap) {
            ChatAskReportLeafContent(source: source, searchQuery: searchQuery, compact: false)
        }
    }
}

// MARK: - 条目内容通用视图
/// 卡片内部纯内容视图，区分 紧凑模式 / 标准模式
struct ChatAskReportLeafContent: View {
    /// 数据源
    let source: ChatSelectableHealthSource
    /// 搜索关键词
    let searchQuery: String
    /// 是否为紧凑布局（子条目使用紧凑，独立卡片使用标准）
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            // 标题（根据布局切换字号，关键词高亮）
            highlightedText(source.title, query: searchQuery)
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
            // 副标题（非空展示，区分字号）
            if let subtitle = source.subtitle, subtitle.isEmpty == false {
                highlightedText(subtitle, query: searchQuery)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
            // 简介：仅标准模式展示，最多2行
            if let summary = source.summary, summary.isEmpty == false, compact == false {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            // 标签组（存在标签时横向展示）
            if source.badges.isEmpty == false {
                ChatAskReportBadgeRow(badges: source.badges)
            }
            // 资源类型本地化文本
            Text(L10n.text(source.resourceType.localizationKey))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 标签行视图
/// 横向滚动的标签组视图
struct ChatAskReportBadgeRow: View {
    /// 标签文本数组
    let badges: [String]

    var body: some View {
        // 横向滚动，隐藏滚动条
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // 胶囊型标签背景
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }
            }
        }
    }
}

// MARK: - 数量统计格式化工具
/// 病历分组子项数量统计格式化工具类，拼接各类档案数量文本
enum ChatAskReportRelatedCountFormatter {
    /// 统计并格式化病历下各类子条目数量，返回拼接后的本地化文本
    /// - Parameter source: 病历分组数据源
    /// - Returns: 格式化后的统计字符串，无数据则返回nil
    static func format(_ source: ChatSelectableHealthSource) -> String? {
        // 非病历分组、无下级条目直接返回nil
        guard source.isMedicalCaseGroup, source.children.isEmpty == false else { return nil }
        
        // 分类统计各类档案数量
        let reports = source.children.filter { $0.resourceType == .examinationReport }.count
        let prescriptions = source.children.filter { $0.resourceType == .prescription }.count
        let plans = source.children.filter { $0.resourceType == .medicationPlan }.count
        let symptoms = source.children.filter { $0.resourceType == .symptom }.count
        let visits = source.children.filter { $0.resourceType == .visit }.count
        let surgeries = source.children.filter { $0.resourceType == .surgery }.count
        let followUps = source.children.filter { $0.resourceType == .followUp }.count
        
        var parts: [String] = []
        // 根据数量拼接对应本地化文案
        if reports > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.reports_format", reports))
        }
        if prescriptions > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.prescriptions_format", prescriptions))
        }
        if plans > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.plans_format", plans))
        }
        if symptoms > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.symptoms_format", symptoms))
        }
        if visits > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.visits_format", visits))
        }
        if surgeries > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.surgeries_format", surgeries))
        }
        if followUps > 0 {
            parts.append(L10n.format("chat.ask_report.sheet.count.follow_ups_format", followUps))
        }
        
        // 无统计数据返回nil，有数据用 · 拼接返回
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 搜索关键词高亮工具方法
/// 文本关键词高亮处理，忽略大小写、重音符号匹配
/// - Parameters:
///   - text: 原始文本
///   - query: 搜索关键词
/// - Returns: 拼接后的富文本视图，匹配内容标主题色+加粗
@ViewBuilder
func highlightedText(_ text: String, query: String) -> some View {
    // 去除关键词首尾空白字符
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // 关键词为空，直接返回原文本
    if trimmedQuery.isEmpty {
        Text(text)
    }
    // 匹配到关键词，拆分文本并高亮匹配部分
    else if let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) {
        let before = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])
        // 前半段 + 高亮匹配段 + 后半段 拼接
        (
            Text(before)
            + Text(match).foregroundColor(.accentColor).fontWeight(.semibold)
            + Text(after)
        )
    }
    // 未匹配到关键词，直接返回原文本
    else {
        Text(text)
    }
}
