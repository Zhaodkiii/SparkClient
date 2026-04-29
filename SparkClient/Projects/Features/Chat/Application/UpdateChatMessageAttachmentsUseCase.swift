import Foundation

struct UpdateChatMessageBlocksUseCase: Sendable {
    let repository: any ChatRepository

    func execute(
        clientMessageID: UUID,
        blocks: [ChatMessageBlock],
        markPendingForSync: Bool = true
    ) async {
        await repository.updateMessageBlocks(
            clientMessageID: clientMessageID,
            blocks: blocks,
            markPendingForSync: markPendingForSync
        )
    }
}
