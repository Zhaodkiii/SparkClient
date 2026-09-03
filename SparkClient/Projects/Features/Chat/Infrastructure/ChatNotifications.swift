import Foundation

nonisolated enum ChatConversationChangeKind: String, Sendable {
    case threadsChanged
    case messagesAppended
    case messagesUpdated
    case messagesMerged
}

nonisolated struct ChatConversationChangeEvent: Sendable {
    let threadID: UUID?
    let kind: ChatConversationChangeKind
    let affectedClientMessageIDs: [UUID]
    let affectsThreadList: Bool

    static let genericThreadsChanged = ChatConversationChangeEvent(
        threadID: nil,
        kind: .threadsChanged,
        affectedClientMessageIDs: [],
        affectsThreadList: true
    )
}

nonisolated extension Notification.Name {
    /// 聊天持久化写入已提交（Core Data 后台上下文 save 成功）。用于 Query 层驱动 UI 刷新。
    static let sparkChatDatabaseDidChange = Notification.Name("SparkClient.sparkChatDatabaseDidChange")
    /// CHAT-000056 Q8：实时定向拉取成功完成（object 为 threadID 的 UUID）。
    /// 表现层据此刷新当前打开医院会话的 context/capabilities（下架/终结 → 立即只读）。
    static let chatRealtimeThreadPullDidComplete = Notification.Name("SparkClient.chatRealtimeThreadPullDidComplete")
}

nonisolated extension Notification {
    var chatConversationChangeEvent: ChatConversationChangeEvent? {
        object as? ChatConversationChangeEvent
    }

    /// `chatRealtimeThreadPullDidComplete` 的负载：完成定向拉取的 threadID。
    var chatRealtimePulledThreadID: UUID? {
        object as? UUID
    }
}
