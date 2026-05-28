import Foundation

/// 会话 metadata 更新：标题/图标/颜色/置顶状态。
struct UpdateChatThreadMetadataUseCase: Sendable {
    let repository: any ChatRepository

    func updateAppearance(
        threadID: UUID,
        title: String,
        iconName: String?,
        iconColorName: String?
    ) async {
        await repository.updateThreadAppearance(
            threadID: threadID,
            title: title,
            iconName: iconName,
            iconColorName: iconColorName
        )
    }

    func updatePinState(threadID: UUID, isPinned: Bool, pinnedAt: Date?) async {
        await repository.updateThreadPinState(
            threadID: threadID,
            isPinned: isPinned,
            pinnedAt: pinnedAt
        )
    }
}

