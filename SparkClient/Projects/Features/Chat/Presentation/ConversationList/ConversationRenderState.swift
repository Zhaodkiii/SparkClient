import Foundation

/// 会话列表一帧的渲染输入：持久化消息 + 可选尾部流式草稿（行键统一为 `clientMessageID`）。
//struct ConversationRenderState: Equatable, Sendable {
//    var items: [ChatMessage]
//
//    static func mergedList(persisted: [ChatMessage], streamingTail: ChatMessage?) -> [ChatMessage] {
//        var items = persisted
//        guard let tail = streamingTail else { return items }
//        if let idx = items.firstIndex(where: { $0.clientMessageID == tail.clientMessageID }) {
//            items[idx] = tail
//        } else {
//            items.append(tail)
//        }
//        return items
//    }
//}



struct ConversationRenderState: Equatable, Sendable {
    var items: [ChatMessage]

    static func mergedList(persisted: [ChatMessage], streamingTail: ChatMessage?) -> [ChatMessage] {
        // 👇 1. 先对持久化消息去重（防止源头重复）
        var items = persisted.removingDuplicates(by: \.clientMessageID)
        
        guard let tail = streamingTail else { return items }
        
        // 替换或追加流式消息
        if let idx = items.firstIndex(where: { $0.clientMessageID == tail.clientMessageID }) {
            items[idx] = tail
        } else {
            items.append(tail)
        }
        
        // 👇 2. 最终再保险去重（100% 不重复）
        return items.removingDuplicates(by: \.clientMessageID)
    }
}

extension Array {
    /// 按自定义 Key 去重（比如 clientMessageID）
    func removingDuplicates<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

