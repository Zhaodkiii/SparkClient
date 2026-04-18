import Foundation

/// 详情页对本地消息窗口的一次加载意图（对齐「请求 → 执行」的单一入口）。
enum ChatLoadRequest: Equatable, Sendable {
    /// 打开会话或整窗重读：从最新端拉 `ChatMessageWindow.newestFetchLimit` 条。
    case openOrReloadNewest(threadID: UUID, skipRemoteSync: Bool, lockBottomViewport: Bool)
    /// 向上分页：在已有 `before` 游标之前再拉一页。
    case loadOlderPage(threadID: UUID, before: Date)

    var threadID: UUID {
        switch self {
        case .openOrReloadNewest(let id, _, _):
            return id
        case .loadOlderPage(let id, _):
            return id
        }
    }
}
