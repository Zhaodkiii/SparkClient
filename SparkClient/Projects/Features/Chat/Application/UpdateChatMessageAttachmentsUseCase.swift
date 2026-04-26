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
        content: String,
        kind: ChatMessageKind,
        attachments: [ChatAttachment],
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        markPendingForSync: Bool = true
    ) async {
        await repository.updateMessageContentAndAttachments(
            clientMessageID: clientMessageID,
            content: content,
            kind: kind,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            markPendingForSync: markPendingForSync
        )
    }
}
