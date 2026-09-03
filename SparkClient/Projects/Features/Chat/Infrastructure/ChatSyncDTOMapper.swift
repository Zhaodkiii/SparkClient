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
            temperature: remote.temperature,
            topP: remote.topP ?? 1.0,
            maxTokens: remote.maxTokens,
            maxMessages: remote.maxMessages ?? 20,
            rolePrompt: remote.rolePrompt ?? "",
            imageDeliveryModeRaw: remote.imageDeliveryModeRaw,
            iconName: remote.iconName,
            iconColorName: remote.iconColorName,
            isPinned: remote.isPinned ?? false,
            pinnedAt: remote.pinnedAt,
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
            let deliveryState = ChatDeliveryState(rawValue: remote.deliveryState)
        else {
            return nil
        }

        return ChatMessage(
            threadID: remote.threadId,
            role: role,
            blocks: remote.blocks,
            clientMessageID: remote.clientMessageId,
            serverMessageID: remote.serverMessageId,
            deliveryState: deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.tombstone,
            modelName: remote.modelName,
            sender: remote.sender.map { remoteSender in
                ChatMessageSender(
                    actorType: ChatMessageSenderActorType(rawValue: remoteSender.actorType),
                    actorId: remoteSender.actorId,
                    displayName: remoteSender.displayName,
                    avatarUrl: remoteSender.avatarUrl,
                    title: remoteSender.title,
                    departmentName: remoteSender.departmentName,
                    source: remoteSender.source
                )
            }
        )
    }
}
