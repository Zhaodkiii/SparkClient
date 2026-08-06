import Foundation

nonisolated enum DeepTutorConversationChangeKind: String, Sendable {
    case threadsChanged
    case messagesAppended
    case messagesUpdated
    case titleUpdated
}

nonisolated struct DeepTutorConversationChangeEvent: Sendable {
    let conversationID: UUID?
    let kind: DeepTutorConversationChangeKind
    let affectedMessageIDs: [UUID]
    let affectsConversationList: Bool

    static let genericThreadsChanged = DeepTutorConversationChangeEvent(
        conversationID: nil,
        kind: .threadsChanged,
        affectedMessageIDs: [],
        affectsConversationList: true
    )
}

nonisolated extension Notification.Name {
    static let deepTutorChatDatabaseDidChange = Notification.Name("SparkClient.deepTutorChatDatabaseDidChange")
}

nonisolated extension Notification {
    var deepTutorConversationChangeEvent: DeepTutorConversationChangeEvent? {
        object as? DeepTutorConversationChangeEvent
    }
}
