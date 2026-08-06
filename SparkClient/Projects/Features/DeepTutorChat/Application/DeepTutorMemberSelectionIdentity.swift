import Foundation

enum DeepTutorMemberSelectionIdentity: Sendable {
    nonisolated static func submitKey(
        assistantMessageID: UUID,
        toolCallID: String,
        memberID: Int
    ) -> String {
        "\(assistantMessageID.uuidString)|\(toolCallID)|\(memberID)"
    }

    nonisolated static func blockKey(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        toolName: String
    ) -> String {
        "\(conversationID.uuidString)|\(assistantMessageID.uuidString)|\(toolCallID)|\(toolName)"
    }

    nonisolated static func matchesExistingBlock(
        existing: DeepTutorMemberSelectionBlockPayload,
        toolCallID: String,
        reason: String
    ) -> Bool {
        if existing.toolCallID == toolCallID {
            return true
        }
        if existing.toolCallID.isEmpty == false,
           toolCallID.isEmpty == false,
           existing.toolCallID != toolCallID {
            return false
        }
        return existing.reason == reason && existing.status == .pending
    }
}
