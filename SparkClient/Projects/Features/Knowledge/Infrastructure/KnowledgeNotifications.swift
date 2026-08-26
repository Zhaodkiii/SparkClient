import Foundation

nonisolated extension Notification.Name {
    /// 知识文档本地写入已提交（创建/更新/删除）。`KnowledgeSyncSupervisor` 据此防抖触发 Push。
    static let sparkKnowledgeDatabaseDidChange = Notification.Name("SparkClient.sparkKnowledgeDatabaseDidChange")
}
