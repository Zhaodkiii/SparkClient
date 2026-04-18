import Foundation

enum ChatConversationChangeKind: String, Sendable {
    case threadsChanged
    case messagesAppended
    case messagesUpdated
    case messagesMerged
}

struct ChatConversationChangeEvent: Sendable {
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

extension Notification.Name {
    /// 聊天持久化写入已提交（Core Data 后台上下文 save 成功）。用于 Query 层驱动 UI 刷新。
    static let sparkChatDatabaseDidChange = Notification.Name("SparkClient.sparkChatDatabaseDidChange")
}

extension Notification {
    var chatConversationChangeEvent: ChatConversationChangeEvent? {
        object as? ChatConversationChangeEvent
    }
}
