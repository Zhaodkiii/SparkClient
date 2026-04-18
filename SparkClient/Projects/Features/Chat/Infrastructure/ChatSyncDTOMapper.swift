import Foundation

/// `ChatRemoteMessageDTO` → ``ChatMessage`` 映射，供同步引擎与出站管线共用。
enum ChatSyncEngineDTOMapper: Sendable {
    nonisolated static func toDomain(_ remote: ChatRemoteMessageDTO) -> ChatMessage? {
        guard
            let role = ChatMessageRole(rawValue: remote.role),
            let kind = ChatMessageKind(rawValue: remote.kind),
            let deliveryState = ChatDeliveryState(rawValue: remote.deliveryState)
        else {
            return nil
        }

        let visibility = ChatReasoningVisibility(rawValue: remote.reasoningVisibility ?? "") ?? .full
        return ChatMessage(
            threadID: remote.threadID,
            role: role,
            kind: kind,
            content: remote.content,
            attachments: remote.attachments ?? [],
            reasoningContent: remote.reasoningContent,
            reasoningDurationMs: remote.reasoningDurationMs,
            reasoningExpanded: remote.reasoningExpanded ?? false,
            reasoningVisibility: visibility,
            clientMessageID: remote.clientMessageID,
            serverMessageID: remote.serverMessageID,
            deliveryState: deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.isTombstone
        )
    }
}
