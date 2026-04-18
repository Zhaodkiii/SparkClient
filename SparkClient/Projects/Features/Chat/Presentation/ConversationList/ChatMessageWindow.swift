import Foundation

/// 会话详情页「消息窗口」参数：从 Core Data 拉取的最新一段消息条数，以及向上分页大小。
enum ChatMessageWindow: Sendable {
    /// 冷启动进入会话时至少拉取的消息条数。
    static let initialNewestLimit = 6
    /// 顶部「加载更多」每次追加的条数。
    static let loadOlderPageSize = 10

    /// 进入会话或同步后重读窗口时，fetch limit 不应小于内存中已有条数，否则会截断已分页窗口。
    static func newestFetchLimit(persistedCount: Int, baseLimit: Int = initialNewestLimit) -> Int {
        max(baseLimit, persistedCount)
    }
}
