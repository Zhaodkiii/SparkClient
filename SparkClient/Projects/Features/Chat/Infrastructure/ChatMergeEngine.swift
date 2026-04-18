import Foundation

/// 入站 / 出站合并的单一真相源：替代分散在 `ChatMergePolicy` 与 `CoreDataChatStore.shouldKeepLocal` 的规则。
struct ChatMergeEngine: Sendable {
    nonisolated init() {}

    /// 与旧 `ChatMergePolicy.resolve` 语义一致：用于出站 push 后合并、入站前预合并。
    nonisolated func resolve(local: ChatMessage?, remote: ChatMessage) -> ChatMessage {
        guard let local else {
            return remote
        }

        if ChatMessage.shouldPreferRemoteUserImageSyncData(local: local, remote: remote) {
            return remote
        }

        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (.some(localDate), .some(remoteDate)):
            return remoteDate >= localDate ? remote : local
        case (.none, .some):
            return remote
        case (.some, .none):
            return local
        case (.none, .none):
            return remote
        }
    }

    /// `true` 表示**跳过**用 `remote` 覆盖本地行（本地胜出或等价于旧 `shouldKeepLocal`）。
    nonisolated func shouldSkipApplyingRemote(local: ChatMessage, remote: ChatMessage) -> Bool {
        if ChatMessage.shouldPreferRemoteUserImageSyncData(local: local, remote: remote) {
            return false
        }
        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (.some(localDate), .some(remoteDate)):
            return localDate > remoteDate
        case (.some, .none):
            return true
        default:
            return false
        }
    }
}

/// 兼容旧构造与参数类型名。
typealias ChatMergePolicy = ChatMergeEngine
