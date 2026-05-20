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
        await repository.updateMessageDeliveryState(clientMessageID: message.clientMessageID, state: .sending)
    }

    func markFailed(_ message: ChatMessage) async {
        await repository.updateMessageDeliveryState(clientMessageID: message.clientMessageID, state: .failed)
    }

    func markSent(_ message: ChatMessage) async {
        await repository.updateMessageDeliveryState(clientMessageID: message.clientMessageID, state: .sent)
        await repository.markMessageBlocksSynced(ids: message.blocks.map(\.id))
    }
}
