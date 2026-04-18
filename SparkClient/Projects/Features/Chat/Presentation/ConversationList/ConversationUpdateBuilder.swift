import Foundation

/// 由前后两帧消息数组推导列表更新计划（供 `UICollectionView` 做 minor / diff / prepend 锚点等）。
enum ConversationUpdateBuilder: Sendable {
    static func plan(previous: [ChatMessage], current: [ChatMessage]) -> ConversationUpdatePlan {
        let previousIDs = previous.map(\.clientMessageID)
        let currentIDs = current.map(\.clientMessageID)
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.clientMessageID, $0) })
        let reloaded = current.compactMap { message -> UUID? in
            guard let old = previousByID[message.clientMessageID] else { return nil }
            return old == message ? nil : message.clientMessageID
        }

        guard previous.isEmpty == false else {
            return ConversationUpdatePlan(
                kind: .reloadAll,
                reloadedItemIDs: reloaded,
                prependedItemIDs: [],
                appendedItemIDs: currentIDs
            )
        }

        if previousIDs == currentIDs {
            return ConversationUpdatePlan(
                kind: .minor,
                reloadedItemIDs: reloaded,
                prependedItemIDs: [],
                appendedItemIDs: []
            )
        }

        let prepended: [UUID]
        if currentIDs.count >= previousIDs.count,
           Array(currentIDs.suffix(previousIDs.count)) == previousIDs {
            prepended = Array(currentIDs.prefix(currentIDs.count - previousIDs.count))
        } else {
            prepended = []
        }

        let appended: [UUID]
        if currentIDs.count >= previousIDs.count,
           Array(currentIDs.prefix(previousIDs.count)) == previousIDs {
            appended = Array(currentIDs.suffix(currentIDs.count - previousIDs.count))
        } else {
            appended = []
        }

        return ConversationUpdatePlan(
            kind: .structural,
            reloadedItemIDs: reloaded,
            prependedItemIDs: prepended,
            appendedItemIDs: appended
        )
    }
}
