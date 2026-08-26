import Foundation

/// 复用 Thread 的判定原因。
enum ChatThreadReuseReason: Equatable, Sendable {
    /// 30 分钟内存在最近活跃 Thread，优先复用。
    case recentActive
    /// 30 分钟内无活跃 Thread，但候选范围内最近一条 Thread 尚未开始（无 user message），复用。
    case latestUnstarted
    /// 当前请求加入了另一个请求正在创建的同一 Thread。
    case joinedCreation
}

/// 纯选择器结果：是否命中可复用 Thread，以及命中原因。
enum ChatThreadReuseDecision: Equatable, Sendable {
    case reuse(threadID: UUID, reason: ChatThreadReuseReason)
    case noReusableThread
}

/// Chat 会话选择策略（CHAT-000041）。
///
/// 该策略同时被对话 Tab 的自动进入和健康资源快捷对话使用，避免两处
/// 对“30 分钟内活跃”的定义产生漂移。核心规则：
/// 1. 优先复用 30 分钟内最近活跃 Thread。
/// 2. 无近期活跃 Thread 时，只检查候选范围内唯一最近的一条 Thread：
///    它没有 user message（未开始会话）则复用，否则不返回可复用结果，绝不继续向后搜索更早的空白 Thread。
struct RecentActiveChatThreadSelector {
    static let defaultActiveInterval: TimeInterval = 30 * 60

    /// 候选范围：当前账号、未删除、chat 场景，且满足可选成员过滤。
    /// - Parameter memberID: nil 表示全局（对话 Tab），非 nil 表示严格同成员（医疗资料入口）。
    private static func candidateThreads(
        in items: [ChatThreadListItem],
        memberID: Int?
    ) -> [ChatThreadListItem] {
        items.filter { item in
            item.thread.scenario == .chat
                && item.thread.isDeleted == false
                && item.thread.deletedAt == nil
                && (memberID == nil || item.thread.memberID == memberID)
        }
    }

    /// 按 `latestMessageAt` 降序、UUID 升序稳定取得最近一条 Thread。
    /// - Parameter activeSince: 非 nil 时只保留 `latestMessageAt >= activeSince` 的近期活跃 Thread。
    private static func mostRecent(
        in candidates: [ChatThreadListItem],
        activeSince: Date?
    ) -> ChatThreadListItem? {
        let pool: [ChatThreadListItem]
        if let activeSince {
            pool = candidates.filter { $0.latestMessageAt >= activeSince }
        } else {
            pool = candidates
        }
        return pool.max { lhs, rhs in
            if lhs.latestMessageAt != rhs.latestMessageAt {
                return lhs.latestMessageAt < rhs.latestMessageAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    /// 统一决策入口：返回可复用 Thread 及原因。
    static func selection(
        in items: [ChatThreadListItem],
        within interval: TimeInterval = defaultActiveInterval,
        memberID: Int? = nil,
        now: Date = Date()
    ) -> ChatThreadReuseDecision {
        let candidates = candidateThreads(in: items, memberID: memberID)
        guard candidates.isEmpty == false else { return .noReusableThread }

        // 1. 近期活跃优先。
        if interval >= 0 {
            let cutoff = now.addingTimeInterval(-interval)
            if let active = mostRecent(in: candidates, activeSince: cutoff) {
                return .reuse(threadID: active.id, reason: .recentActive)
            }
        }

        // 2. 只检查最近一条 Thread 是否未开始。
        if let latest = mostRecent(in: candidates, activeSince: nil),
           latest.hasUserMessage == false {
            return .reuse(threadID: latest.id, reason: .latestUnstarted)
        }

        return .noReusableThread
    }

    /// 兼容旧接口：仅返回 30 分钟内最近活跃 Thread ID（不含空白会话复用）。
    static func mostRecentActiveThreadID(
        in items: [ChatThreadListItem],
        within interval: TimeInterval = defaultActiveInterval,
        memberID: Int? = nil,
        now: Date = Date()
    ) -> UUID? {
        guard interval >= 0 else { return nil }
        let cutoff = now.addingTimeInterval(-interval)
        return mostRecent(
            in: candidateThreads(in: items, memberID: memberID),
            activeSince: cutoff
        )?.id
    }
}
