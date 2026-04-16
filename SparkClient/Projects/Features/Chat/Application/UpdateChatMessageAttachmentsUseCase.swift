import Foundation

struct UpdateChatMessageAttachmentsUseCase: Sendable {
    let repository: any ChatRepository

    func execute(
        clientMessageID: UUID,
        attachments: [ChatAttachment],
        markPendingForSync: Bool = true
    ) async {
        await repository.updateMessageAttachments(
            clientMessageID: clientMessageID,
            attachments: attachments,
            markPendingForSync: markPendingForSync
        )
    }
}

