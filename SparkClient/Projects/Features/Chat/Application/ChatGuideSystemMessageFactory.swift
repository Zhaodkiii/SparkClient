import Foundation

/// 新会话首条系统引导消息工厂：
/// 保证角色（system）、block 状态（ready）、稳定 block id、deliveryState（pending 进入 outbox 同步）。
enum ChatGuideSystemMessageFactory {
    static func make(
        threadID: UUID,
        payload: ChatGuideCardPayload,
        createdAt: Date = Date()
    ) -> ChatMessage {
        let messageID = UUID()
        let block = ChatMessageBlock.fromPayload(
            .chatGuideCard(payload),
            id: ChatStableBlockID.rich(messageID: messageID, kind: .chatGuideCard),
            orderKey: 0,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        return ChatMessage(
            threadID: threadID,
            role: .system,
            blocks: [block],
            clientMessageID: messageID,
            deliveryState: .pending,
            createdAt: createdAt
        )
    }
}
