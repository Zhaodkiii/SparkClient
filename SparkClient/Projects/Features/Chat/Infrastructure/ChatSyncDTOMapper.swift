import Foundation

/// `ChatRemoteMessageDTO` → ``ChatMessage`` 映射，供同步引擎与出站管线共用。
enum ChatSyncEngineDTOMapper: Sendable {
    nonisolated static func toDomainThread(_ remote: ChatRemoteThreadDTO) -> ChatThread? {
        guard let scenario = AIScenario(rawValue: remote.scenario) else { return nil }
        return ChatThread(
            id: remote.threadID,
            memberID: remote.memberID,
            title: remote.title,
            scenario: scenario,
            currentModelName: remote.currentModelName,
            temperature: remote.temperature ?? 0.6,
            topP: remote.topP ?? 1.0,
            maxTokens: remote.maxTokens ?? 4096,
            maxMessages: remote.maxMessages ?? 20,
            rolePrompt: remote.rolePrompt ?? "",
            imageDeliveryModeRaw: remote.imageDeliveryModeRaw,
            isDeleted: remote.isDeleted,
            deletedAt: remote.deletedAt,
            createdAt: remote.updatedAt,
            updatedAt: remote.updatedAt,
            serverUpdatedAt: remote.serverUpdatedAt
        )
    }

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
            blocks: remote.blocks,
            reasoningContent: remote.reasoningContent,
            reasoningDurationMs: remote.reasoningDurationMs,
            reasoningExpanded: remote.reasoningExpanded ?? false,
            reasoningVisibility: visibility,
            clientMessageID: remote.clientMessageID,
            serverMessageID: remote.serverMessageID,
            deliveryState: deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.isTombstone,
            modelName: remote.modelName
        )
    }
}
