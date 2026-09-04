import SwiftUI

/// CHAT-000057 17.2/D-007：统一消息卡片行。
///
/// 三类会话（普通 AI / 院内医生智能体 / 线上问诊预留）与 unknown 共用同一布局骨架；
/// 类型差异全部来自 `UnifiedConversationListItem` 的结构化投影字段，View 不解析服务端字符串、
/// 不按标题/头像猜测类型。
struct UnifiedConversationRow: View {
    let item: UnifiedConversationListItem
    /// 由页面传入的已格式化最近时间（复用列表页「今天 HH:mm / 昨天 / MM-dd」规则）。
    let formattedDate: String
    /// unknown 确认失败后的重试回调；仅 `.retryableFailure` 状态展示。
    var onRetryConfirmation: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 6) {
                headerLine
                badgeLine
                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let threadLine {
                    Text(threadLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if item.latestMessagePreview.isEmpty == false {
                    Text(item.latestMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                retryLineIfNeeded
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - 头像（17.3 矩阵）

    @ViewBuilder
    private var avatarView: some View {
        switch item.avatar {
        case .threadAppearance(let iconName, let iconColorName):
            let icon = (iconName?.isEmpty == false ? iconName : nil) ?? "bubble.left.circle"
            let colorName = (iconColorName?.isEmpty == false ? iconColorName : nil) ?? "accent"
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(ChatThreadAppearanceResources.color(from: colorName))
                .padding(6)
                .background(Circle().fill(.thinMaterial))
        case .doctor(let displayName, let avatarURL),
             .telemedicine(let displayName, let avatarURL):
            doctorAvatar(displayName: displayName, avatarURL: avatarURL)
        case .neutralPending:
            // unknown：中性会话占位，不使用 AI/医生/医院头像（17.6）。
            Image(systemName: "bubble.left.and.text.bubble.right")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Circle().fill(.thinMaterial))
        }
    }

    /// 医生/问诊头像：真实头像优先，缺失时姓名首字占位（17.6）。加载复用通用文件缓存。
    @ViewBuilder
    private func doctorAvatar(displayName: String?, avatarURL: URL?) -> some View {
        ZStack {
            Circle().fill(.thinMaterial)
            HospitalAvatarImageView(
                urlString: avatarURL?.absoluteString ?? "",
                size: 46,
                placeholderText: String(displayName?.prefix(1) ?? ""),
                accent: .secondary
            )
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
    }

    // MARK: - 第一行：主标题 + 置顶 + 时间

    private var headerLine: some View {
        HStack(spacing: 8) {
            Text(item.primaryTitle)
                .font(.headline)
                .lineLimit(1)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 第二行：类型标识 + 服务状态 + 未读角标

    @ViewBuilder
    private var badgeLine: some View {
        HStack(spacing: 6) {
            badgeChip(
                title: item.typeBadge.localizedTitle,
                tint: badgeTint(item.typeBadge)
            )
            // 服务状态只显示对患者当前操作有影响的一个主状态（17.4）。
            if let statusBadge = item.serviceStatus?.localizedBadge {
                badgeChip(title: statusBadge, tint: .orange)
            }
            Spacer()
            if item.unreadCount > 0 {
                Text(item.unreadCount > 99 ? "99+" : String(item.unreadCount))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .accessibilityLabel(
                        L10n.text("chat.unified.unread.accessibility", fallback: "未读消息")
                            + " \(item.unreadCount)"
                    )
            }
        }
    }

    private func badgeChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    /// 类型标识颜色仅作辅助，文字必须存在（17.8.7）。
    private func badgeTint(_ badge: ConversationTypeBadge) -> Color {
        switch badge {
        case .ordinaryAI:
            return ChatThreadAppearanceResources.color(from: "hlBlue")
        case .hospitalAgent:
            return ChatThreadAppearanceResources.color(from: "hlGreen")
        case .telemedicine:
            return .purple
        case .confirming, .confirmationFailed:
            return .secondary
        }
    }

    // MARK: - 副标题与「会话：」行

    /// 副标题：医院会话为智能体名称，其后可拼接成员标识（D-009）。
    private var secondaryLine: String? {
        var parts: [String] = []
        if let secondary = item.secondaryIdentity, secondary.isEmpty == false {
            parts.append(secondary)
        }
        if let member = item.memberDisplayName, member.isEmpty == false {
            parts.append(member)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 医院/unknown 会话保留 Thread 标题为独立「会话：」行（D-008）；普通 AI 不重复展示。
    private var threadLine: String? {
        guard item.conversationKind != .ordinaryAI,
              let title = item.threadTitle,
              title.isEmpty == false,
              title != item.primaryTitle else { return nil }
        return L10n.text("chat.unified.thread_title.prefix", fallback: "会话：") + title
    }

    // MARK: - unknown 确认失败重试

    @ViewBuilder
    private var retryLineIfNeeded: some View {
        if item.classificationState == .retryableFailure, let onRetryConfirmation {
            Button(action: onRetryConfirmation) {
                Label(
                    L10n.text("chat.unified.unknown.retry", fallback: "重试确认"),
                    systemImage: "arrow.clockwise"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - 可访问性（17.8.5：组合朗读，避免重复装饰性标签）

    private var accessibilitySummary: String {
        var parts = [item.primaryTitle, item.typeBadge.localizedTitle]
        if let status = item.serviceStatus?.localizedBadge {
            parts.append(status)
        }
        if item.latestMessagePreview.isEmpty == false {
            parts.append(item.latestMessagePreview)
        }
        parts.append(formattedDate)
        if item.unreadCount > 0 {
            parts.append(
                L10n.text("chat.unified.unread.accessibility", fallback: "未读消息")
                    + " \(item.unreadCount)"
            )
        }
        return parts.joined(separator: ", ")
    }
}
