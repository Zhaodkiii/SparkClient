import Foundation

nonisolated extension Notification.Name {
    /// 记忆条目或设置已写入本地存储。仅用于 UI 刷新，不代表需要上传。
    static let sparkMemoryDatabaseDidChange = Notification.Name("SparkClient.sparkMemoryDatabaseDidChange")

    /// 用户本地创建/编辑/删除记忆条目并已入 Outbox。`MemorySyncSupervisor` 据此防抖触发同步。
    static let sparkMemoryLocalMutationDidHappen = Notification.Name("SparkClient.sparkMemoryLocalMutationDidHappen")
}
