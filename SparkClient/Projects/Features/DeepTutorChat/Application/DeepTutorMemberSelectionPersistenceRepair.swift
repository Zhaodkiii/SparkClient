import Foundation

enum DeepTutorMemberSelectionPersistenceRepair: Sendable {
    nonisolated static func normalized(_ message: DeepTutorMessage) -> DeepTutorMessage {
        guard message.role == .assistant else { return message }

        let resolvedEvents = message.events.compactMap { event -> (toolCallID: String, memberID: Int, memberName: String?)? in
            if case let .memberSelectionResolved(toolCallID, memberID, memberName) = event {
                return (toolCallID, memberID, memberName)
            }
            return nil
        }
        guard resolvedEvents.isEmpty == false else { return message }

        let memberSelectionBlocks = message.blocks.filter { $0.kind == .memberSelection }
        guard memberSelectionBlocks.isEmpty == false else { return message }

        var changed = false
        let updatedBlocks = message.blocks.map { block -> DeepTutorMessageBlock in
            guard block.kind == .memberSelection,
                  case var .memberSelection(payload) = block.payload else {
                return block
            }

            let resolved = resolvedEvents.first(where: { $0.toolCallID == payload.toolCallID })
                ?? singleResolvedFallback(
                    resolvedEvents: resolvedEvents,
                    memberSelectionBlockCount: memberSelectionBlocks.count
                )
            guard let resolved else {
                DeepTutorChatLog.memberSelectionPersistProbe(
                    phase: "repair_no_match",
                    conversationID: message.conversationID,
                    messageID: message.id,
                    source: "normalizer",
                    summary: DeepTutorChatLog.memberSelectionSummary(for: message),
                    extra: "blockTool=\(payload.toolCallID) resolvedCount=\(resolvedEvents.count)"
                )
                return block
            }

            let selectedMemberName = resolved.memberName ?? payload.selectedMemberName
            if payload.status == .completed,
               payload.selectedMemberID == resolved.memberID,
               payload.selectedMemberName == selectedMemberName {
                return block
            }

            payload.status = .completed
            payload.selectedMemberID = resolved.memberID
            payload.selectedMemberName = selectedMemberName
            payload.resultText = payload.resultText ?? L10n.text("tool.result.request_member_selection.completed")
            payload.updatedAt = Date()
            changed = true
            DeepTutorChatLog.memberSelectionPersistProbe(
                phase: "repair_applied",
                conversationID: message.conversationID,
                messageID: message.id,
                source: "normalizer",
                summary: DeepTutorChatLog.memberSelectionSummary(for: message),
                extra: "blockTool=\(payload.toolCallID) memberID=\(resolved.memberID)"
            )

            return DeepTutorMessageBlock(
                id: block.id,
                kind: block.kind,
                payload: .memberSelection(payload),
                toolCallID: block.toolCallID ?? payload.toolCallID,
                revision: block.revision,
                orderKey: block.orderKey,
                createdAt: block.createdAt,
                updatedAt: Date()
            )
        }

        guard changed else { return message }
        let repaired = message.replacing(blocks: updatedBlocks)
        DeepTutorChatLog.memberSelectionPersistProbe(
            phase: "repair_result",
            conversationID: repaired.conversationID,
            messageID: repaired.id,
            source: "normalizer",
            summary: DeepTutorChatLog.memberSelectionSummary(for: repaired)
        )
        return repaired
    }

    private nonisolated static func singleResolvedFallback(
        resolvedEvents: [(toolCallID: String, memberID: Int, memberName: String?)],
        memberSelectionBlockCount: Int
    ) -> (toolCallID: String, memberID: Int, memberName: String?)? {
        guard memberSelectionBlockCount == 1, resolvedEvents.count == 1 else { return nil }
        return resolvedEvents[0]
    }
}
