import Foundation

enum DeepTutorListLayoutConstants {
    static let loadMoreRowUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!
}

enum DeepTutorConversationUpdateKind: Equatable, Sendable {
    case minor
    case structural
    case reloadAll
}

struct DeepTutorConversationUpdatePlan: Sendable {
    let kind: DeepTutorConversationUpdateKind
    let reloadedItemIDs: [UUID]
    let prependedItemIDs: [UUID]
    let appendedItemIDs: [UUID]

    var hasPrependedItems: Bool { prependedItemIDs.isEmpty == false }
    var hasAppendedItems: Bool { appendedItemIDs.isEmpty == false }
}

struct DeepTutorListApplyPayload: Equatable, Sendable {
    var rowModels: [DeepTutorMessageRowModel]
    var hasMoreMessages: Bool
    var isLoadingMoreMessages: Bool
    var lockBottomViewport: Bool
    var scrollToBottomRequestGeneration: UInt64
    var forceFullListRediff: Bool

    var messages: [DeepTutorMessage] {
        rowModels.map(\.message)
    }
}

struct DeepTutorListApplySignature: Equatable, Sendable {
    let conversationID: UUID
    let contentFingerprint: String
    let hasMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64
    let forceFullListRediff: Bool

    static func make(conversationID: UUID, payload: DeepTutorListApplyPayload) -> DeepTutorListApplySignature {
        let messageFingerprints = payload.rowModels.map { row in
            "\(row.id.uuidString)|sig=\(row.renderSignature)"
        }.joined(separator: ";")
        let loadMore = payload.hasMoreMessages ? "1" : "0"
        let fingerprint = "\(messageFingerprints)|loadMore=\(loadMore)|loadingMore=\(payload.isLoadingMoreMessages)"
        return DeepTutorListApplySignature(
            conversationID: conversationID,
            contentFingerprint: fingerprint,
            hasMoreMessages: payload.hasMoreMessages,
            lockBottomViewport: payload.lockBottomViewport,
            scrollToBottomRequestGeneration: payload.scrollToBottomRequestGeneration,
            forceFullListRediff: payload.forceFullListRediff
        )
    }
}

enum DeepTutorConversationUpdateBuilder: Sendable {
    static func plan(previous: [DeepTutorMessage], current: [DeepTutorMessage]) -> DeepTutorConversationUpdatePlan {
        let previousIDs = previous.map(\.clientMessageID)
        let currentIDs = current.map(\.clientMessageID)
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.clientMessageID, $0) })
        let reloaded = current.compactMap { message -> UUID? in
            guard let old = previousByID[message.clientMessageID] else { return nil }
            return old == message ? nil : message.clientMessageID
        }

        guard previous.isEmpty == false else {
            return DeepTutorConversationUpdatePlan(
                kind: .reloadAll,
                reloadedItemIDs: reloaded,
                prependedItemIDs: [],
                appendedItemIDs: currentIDs
            )
        }

        if previousIDs == currentIDs {
            return DeepTutorConversationUpdatePlan(
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

        return DeepTutorConversationUpdatePlan(
            kind: .structural,
            reloadedItemIDs: reloaded,
            prependedItemIDs: prepended,
            appendedItemIDs: appended
        )
    }
}
