import Foundation

/// 会话列表一帧的渲染输入：持久化消息 + 可选尾部流式草稿（行键统一为 `clientMessageID`）。
struct ConversationRenderState: Equatable, Sendable {
    var items: [ChatMessage]

    static func mergedList(persisted: [ChatMessage], streamingTail: ChatMessage?) -> [ChatMessage] {
        var items = persisted
        guard let tail = streamingTail else { return items }
        if let idx = items.firstIndex(where: { $0.clientMessageID == tail.clientMessageID }) {
            items[idx] = tail
        } else {
            items.append(tail)
        }
        return items
    }
}
