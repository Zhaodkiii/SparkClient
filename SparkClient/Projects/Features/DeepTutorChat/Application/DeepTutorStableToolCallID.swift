import Foundation

/// 为缺失 toolCallID 的历史数据生成稳定 ID，避免 reload 后 identity 漂移。
enum DeepTutorStableToolCallID: Sendable {
    nonisolated static func legacy(prefix: String, seed: String) -> String {
        let normalizedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return "legacy-\(normalizedPrefix)-\(hexHash(seed))"
    }

    nonisolated static func askUserBlock(messageID: UUID, blockID: UUID, prompt: String) -> String {
        legacy(
            prefix: "ask-user",
            seed: "\(messageID.uuidString)|\(blockID.uuidString)|\(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }

    nonisolated static func askUserEvent(messageID: UUID, prompt: String, optionLabels: [String]) -> String {
        legacy(
            prefix: "ask-user",
            seed: "\(messageID.uuidString)|event|\(prompt)|\(optionLabels.joined(separator: "|"))"
        )
    }

    nonisolated static func toolEvent(messageID: UUID, prefix: String, toolName: String, callSeed: String) -> String {
        legacy(
            prefix: prefix,
            seed: "\(messageID.uuidString)|\(toolName)|\(callSeed)"
        )
    }

    private nonisolated static func hexHash(_ seed: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llX", hash)
    }
}
