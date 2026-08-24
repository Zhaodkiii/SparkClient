import Foundation

/// Chat 会话最近活跃选择策略。
///
/// 该策略同时被对话 Tab 的自动进入和健康资源快捷对话使用，避免两处
/// 对“5 分钟内活跃”的定义产生漂移。
struct RecentActiveChatThreadSelector {
    static let defaultActiveInterval: TimeInterval = 5 * 60

    static func mostRecentActiveThreadID(
        in items: [ChatThreadListItem],
        within interval: TimeInterval = defaultActiveInterval,
        memberID: Int? = nil,
        now: Date = Date()
    ) -> UUID? {
        guard interval >= 0 else { return nil }
        let cutoff = now.addingTimeInterval(-interval)

        return items
            .filter { item in
                item.thread.scenario == .chat
                    && item.thread.isDeleted == false
                    && item.thread.deletedAt == nil
                    && (memberID == nil || item.thread.memberID == memberID)
                    && item.latestMessageAt >= cutoff
            }
            .max { lhs, rhs in
                if lhs.latestMessageAt != rhs.latestMessageAt {
                    return lhs.latestMessageAt < rhs.latestMessageAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }?
            .id
    }
}
