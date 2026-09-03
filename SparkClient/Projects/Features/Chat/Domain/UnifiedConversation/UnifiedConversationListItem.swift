import Foundation

/// CHAT-000057 42.2：点击列表卡片后的路由描述符。
/// 任何深链/推送必须先经 Manifest/缓存解析路由，禁止 URL 参数直接决定业务身份。
enum UnifiedConversationRoute: Equatable, Sendable {
    case ordinaryAI(threadID: UUID, memberID: Int?)
    case hospitalAgent(threadID: UUID, hospitalID: UUID, agentID: UUID, memberID: Int)
    case telemedicine(threadID: UUID, consultationID: UUID, memberID: Int?)
    /// unknown：先进入受控确认流程，确认前禁发/禁已读
    case confirmationRequired(threadID: UUID)

    var threadID: UUID {
        switch self {
        case .ordinaryAI(let threadID, _),
             .hospitalAgent(let threadID, _, _, _),
             .telemedicine(let threadID, _, _),
             .confirmationRequired(let threadID):
            return threadID
        }
    }
}

/// CHAT-000057 D-007：卡片头像描述符（结构化，View 只映射样式）。
enum UnifiedConversationAvatar: Equatable, Sendable {
    /// 普通 AI：Thread 自定义图标/颜色或默认 AI 图标
    case threadAppearance(iconName: String?, iconColorName: String?)
    /// 院内医生智能体：真实医生头像，缺失时医生姓名占位
    case doctor(displayName: String?, avatarURL: URL?)
    /// 线上问诊（预留）：真人医生或问诊服务头像
    case telemedicine(displayName: String?, avatarURL: URL?)
    /// unknown：中性会话占位，不使用 AI/医生/医院头像
    case neutralPending
}

/// CHAT-000057 37.3：统一消息列表的唯一 UI 输入投影。
///
/// 由 UnifiedConversationProjector 输出；不持久化消息正文，可由缓存与 Manifest 随时重建。
struct UnifiedConversationListItem: Identifiable, Equatable, Sendable {
    let threadID: UUID
    let memberID: Int?
    let conversationKind: ConversationKind
    let classificationState: ConversationClassificationState
    let serviceStatus: ConversationServiceStatus?
    let capability: ConversationCapability
    /// 主标题：普通 AI 为 Thread 标题；医院会话为医生姓名；unknown 为中性文案
    let primaryTitle: String
    /// 身份副标题：医院会话为智能体名称
    let secondaryIdentity: String?
    /// Thread 标题（医院会话以「会话：」独立行展示；普通 AI 不重复）
    let threadTitle: String?
    let typeBadge: ConversationTypeBadge
    let avatar: UnifiedConversationAvatar
    let latestMessagePreview: String
    let latestMessageAt: Date
    let unreadCount: Int
    let isPinned: Bool
    /// 成员标识：本人 / 成员姓名 / 加载中 / 不可用
    let memberDisplayName: String?
    /// 搜索 token（已 normalize 为小写）：仅身份与标题字段，不含消息正文
    let searchTokens: [String]
    let route: UnifiedConversationRoute
    /// 底层 Thread（外观、置顶等通用事实）
    let thread: ChatThread
    let bindingRevision: Int64?

    var id: UUID { threadID }

    /// 医疗类会话（hospital_agent / telemedicine）：仅允许置顶与「从消息列表移除」。
    var isMedicalKind: Bool {
        conversationKind == .hospitalAgent || conversationKind == .telemedicine
    }

    /// D-026：仅永久 legacy unknown 允许真实删除会话。
    var allowsLegacyDelete: Bool {
        conversationKind == .unknown
    }

    /// D-016：打开会话后是否允许标记已读。
    var canMarkRead: Bool { capability.canMarkRead }
}

// MARK: - 筛选 / 搜索 / 排序（纯函数，供单测穷举）

extension Array where Element == UnifiedConversationListItem {
    /// CHAT-000057 D-010/D-017/D-013：类型筛选 → 搜索 → 置顶区优先、区内最近消息时间倒序、
    /// 同时间按 threadID 升序稳定兜底。
    func visibleItems(
        filter: MessageListTypeFilter,
        query: String
    ) -> [UnifiedConversationListItem] {
        let typeMatched = self.filter { item in
            filter.matches(item.conversationKind)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched: [UnifiedConversationListItem]
        if trimmed.isEmpty {
            searched = typeMatched
        } else {
            searched = typeMatched.filter { item in
                item.searchTokens.contains { $0.contains(trimmed) }
            }
        }
        return searched.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.latestMessageAt != rhs.latestMessageAt {
                return lhs.latestMessageAt > rhs.latestMessageAt
            }
            return lhs.threadID.uuidString < rhs.threadID.uuidString
        }
    }

    /// CHAT-000057 D-015：账号级未读总数（含 unknown；已隐藏/撤权项在投影阶段已被过滤）。
    var aggregatedUnreadCount: Int {
        reduce(0) { $0 + Swift.max(0, $1.unreadCount) }
    }
}

/// CHAT-000057 D-015：分段角标展示文案，1–99 显示实际数字，超过 99 显示 99+，0 隐藏。
func unifiedUnreadBadgeText(_ count: Int) -> String? {
    if count <= 0 { return nil }
    if count > 99 { return "99+" }
    return String(count)
}
