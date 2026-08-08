import Foundation

enum DeepTutorMemberSelectionReloadRecovery: Sendable {
    nonisolated static func preservePendingBlocksOnReload(in messages: [DeepTutorMessage]) -> [DeepTutorMessage] {
        messages.map { preservePendingBlocksOnReload(in: $0) }
    }

    nonisolated static func preservePendingBlocksOnReload(in message: DeepTutorMessage) -> DeepTutorMessage {
        guard message.role == .assistant else { return message }

        let pendingMemberSelectionBlocks = message.blocks.filter { block in
            guard block.kind == .memberSelection,
                  case let .memberSelection(payload) = block.payload else { return false }
            return payload.status == .pending || payload.status == .running
        }
        guard pendingMemberSelectionBlocks.isEmpty == false else { return message }

        var events = message.events
        var didChange = false

        for block in pendingMemberSelectionBlocks {
            guard case let .memberSelection(payload) = block.payload else { continue }
            let hasRequestedEvent = events.contains { event in
                if case let .memberSelectionRequested(_, _, toolCallID) = event {
                    return toolCallID == payload.toolCallID
                }
                return false
            }
            if hasRequestedEvent == false {
                events.append(
                    .memberSelectionRequested(
                        reason: payload.reason,
                        arguments: payload.arguments,
                        toolCallID: payload.toolCallID
                    )
                )
                DeepTutorChatLog.memberSelectionReloadRecoveredPending(
                    conversationID: message.conversationID,
                    assistantMessageID: message.id,
                    blockID: block.id,
                    action: "event_restored"
                )
                didChange = true
            }
        }

        let updatedBlocks = message.blocks.map { block -> DeepTutorMessageBlock in
            guard block.kind == .memberSelection,
                  case var .memberSelection(payload) = block.payload else { return block }
            guard payload.status == .pending || payload.status == .running else { return block }
            if payload.status == .running {
                payload.status = .pending
                payload.updatedAt = Date()
                DeepTutorChatLog.memberSelectionReloadRecoveredPending(
                    conversationID: message.conversationID,
                    assistantMessageID: message.id,
                    blockID: block.id,
                    action: "running_to_pending"
                )
                didChange = true
            }
            return DeepTutorMessageBlock(
                id: block.id,
                kind: block.kind,
                payload: .memberSelection(payload),
                toolCallID: block.toolCallID ?? payload.toolCallID,
                revision: block.revision,
                orderKey: block.orderKey,
                createdAt: block.createdAt,
                updatedAt: didChange ? Date() : block.updatedAt
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
