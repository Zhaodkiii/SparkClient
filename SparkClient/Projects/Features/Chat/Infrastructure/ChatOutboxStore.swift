import Foundation

actor ChatOutboxStore {
    private let repository: any ChatRepository

    init(repository: any ChatRepository) {
        self.repository = repository
    }

    func pending(limit: Int = 50) async -> [ChatMessage] {
        await repository.loadOutboxMessages(limit: limit)
    }

    func pendingBlocks(limit: Int = 100) async -> [ChatPendingMessageBlock] {
        await repository.loadPendingMessageBlocks(limit: limit)
    }

    func markBlocksSynced(ids: [UUID]) async {
        await repository.markMessageBlocksSynced(ids: ids)
    }

    func markSending(_ message: ChatMessage) async {
        await repository.updateMessageDeliveryState(
            clientMessageID: message.clientMessageID,
            state: .sending,
            notifyUI: false
        )
    }

    func markFailed(_ message: ChatMessage) async {
        await repository.updateMessageDeliveryState(clientMessageID: message.clientMessageID, state: .failed)
    }

    func markSent(_ message: ChatMessage, syncedBlockIDs: [UUID]) async {
        await repository.updateMessageDeliveryState(
            clientMessageID: message.clientMessageID,
            state: .sent,
            notifyUI: false
        )
        guard syncedBlockIDs.isEmpty == false else { return }
        await repository.markMessageBlocksSynced(ids: syncedBlockIDs)
    }
}
