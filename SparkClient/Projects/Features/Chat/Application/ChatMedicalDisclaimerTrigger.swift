import Foundation

/// 判定助手消息是否应自动追加医疗免责声明卡片（`TOOL-CALL-000003`）。
enum ChatMedicalDisclaimerTrigger {
    nonisolated static func shouldAppendDisclaimer(to message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return message.blocks.contains(where: isTriggerBlock(_:))
    }

    nonisolated private static func isTriggerBlock(_ block: ChatMessageBlock) -> Bool {
        switch block.kind {
        case .medicalRiskNotice:
            return block.status == .ready
        case .structuredHealthCards:
            guard block.status == .ready,
                  let blob = block.structuredHealthCards,
                  blob.extractionFailed == false,
                  blob.totalCardCount > 0 else {
                return false
            }
            return true
        default:
            return false
        }
    }
}
