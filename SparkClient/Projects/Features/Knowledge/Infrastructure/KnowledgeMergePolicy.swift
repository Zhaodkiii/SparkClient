import Foundation

/// 知识文档冲突解决策略：服务端 `revision` 快照始终优先，不做基于时间戳的 Last-Write-Wins
/// （区别于 `ChatMergeEngine` 的 `serverUpdatedAt` LWW 规则，工单 5.5 明确以 revision 为权威）。
nonisolated struct KnowledgeMergePolicy: Sendable {
    nonisolated init() {}

    /// 过滤出本轮 Pull 应该落地的远端快照：跳过当前存在未终态本地 Outbox 的文档，
    /// 避免吞掉尚未上送的本地编辑（工单 5.7 “remote apply 不得与未发送本地 mutation 冲突”）。
    nonisolated func snapshotsToApply(
        _ snapshots: [KnowledgeRemoteDocumentSnapshot],
        activeOutboxDocumentIDs: Set<UUID>
    ) -> [KnowledgeRemoteDocumentSnapshot] {
        snapshots.filter { activeOutboxDocumentIDs.contains($0.id) == false }
    }

    /// 409（revision 冲突 / 文档已删除）响应始终以服务端快照为权威；不存在“本地更优”分支，
    /// 过期 mutation 转 `resolvedByServer` 并停止重试。
    nonisolated func shouldApplyServerSnapshotOnConflict() -> Bool { true }
}
