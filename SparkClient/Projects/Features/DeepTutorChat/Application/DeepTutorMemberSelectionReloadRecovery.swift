import Foundation

enum DeepTutorMemberSelectionReloadRecovery: Sendable {
    nonisolated static func expireStalePendingBlocks(in messages: [DeepTutorMessage]) -> [DeepTutorMessage] {
        messages.map { expireStalePendingBlocks(in: $0) }
    }

    nonisolated static func expireStalePendingBlocks(in message: DeepTutorMessage) -> DeepTutorMessage {
        guard message.role == .assistant else { return message }

        let hasPendingMemberSelection = message.blocks.contains { block in
            guard block.kind == .memberSelection,
                  case let .memberSelection(payload) = block.payload else { return false }
            return payload.status == .pending || payload.status == .running
        }
        guard hasPendingMemberSelection else { return message }

        // 流式进行中保留 pending；重载后无 continuation，只能标记为中断态。
        guard message.status != .streaming else { return message }

        var events = message.events
        var didChange = false
        for index in events.indices {
            if case let .memberSelectionRequested(reason, arguments, toolCallID) = events[index] {
                let resolved = message.blocks.contains { block in
                    guard block.kind == .memberSelection,
                          case let .memberSelection(payload) = block.payload else { return false }
                    return payload.toolCallID == toolCallID && payload.status == .completed
                }
                if resolved == false {
                    events[index] = .memberSelectionRequested(reason: reason, arguments: arguments, toolCallID: toolCallID)
                    didChange = true
                }
            }
        }

        let updatedBlocks = message.blocks.map { block -> DeepTutorMessageBlock in
            guard block.kind == .memberSelection,
                  case var .memberSelection(payload) = block.payload else { return block }
            guard payload.status == .pending || payload.status == .running else { return block }
            payload.status = .expired
            payload.resultText = "本次成员选择已中断，请重新发送问题。"
            payload.updatedAt = Date()
            DeepTutorChatLog.memberSelectionReloadRecoveredPending(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                blockID: block.id,
                action: "expired"
            )
            didChange = true
            return DeepTutorMessageBlock(
                id: block.id,
                kind: block.kind,
                payload: .memberSelection(payload),
                toolCallID: block.toolCallID,
                revision: block.revision,
                orderKey: block.orderKey,
                createdAt: block.createdAt,
                updatedAt: Date()
            )
        }

        guard didChange else { return message }
        var updated = message.replacing(events: events, blocks: updatedBlocks)
        if updated.status == .streaming {
            updated = updated.replacing(status: .ready)
        }
        return updated
    }
}
