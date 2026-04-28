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

    func execute(
        clientMessageID: UUID,
        attachments: [ChatAttachment],
        blocks: [ChatMessageBlock],
        markPendingForSync: Bool = true
    ) async {
        await repository.updateMessagePresentation(
            clientMessageID: clientMessageID,
            attachments: attachments,
            blocks: blocks,
            markPendingForSync: markPendingForSync
        )
    }

    func execute(
        clientMessageID: UUID,
        content: String,
        kind: ChatMessageKind,
        attachments: [ChatAttachment],
        blocks: [ChatMessageBlock]? = nil,
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        markPendingForSync: Bool = true
    ) async {
        await repository.updateMessageContentAndAttachments(
            clientMessageID: clientMessageID,
            content: content,
            kind: kind,
            attachments: attachments,
            blocks: blocks,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            markPendingForSync: markPendingForSync
        )
    }
}
