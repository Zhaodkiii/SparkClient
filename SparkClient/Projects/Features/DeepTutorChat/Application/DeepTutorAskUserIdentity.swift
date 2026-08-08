import Foundation

enum DeepTutorAskUserIdentity: Sendable {
    nonisolated static func identityKey(
        messageID: UUID,
        blockID: UUID,
        toolCallID: String,
        prompt: String,
        optionLabels: [String]
    ) -> String {
        let trimmedToolCallID = toolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToolCallID.isEmpty == false {
            return "tool:\(trimmedToolCallID)"
        }
        return "block:\(messageID.uuidString)|\(blockID.uuidString)|\(promptHash(prompt, optionLabels: optionLabels))"
    }

    nonisolated static func submitKey(
        assistantMessageID: UUID,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer]
    ) -> String {
        let answersHash = answers
            .map { "\($0.questionID):\($0.text)" }
            .sorted()
            .joined(separator: "|")
        return "\(assistantMessageID.uuidString)|\(toolCallID)|\(answersHash)"
    }

    nonisolated static func matchesExistingBlock(
        existing: DeepTutorAskUserBlockPayload,
        toolCallID: String,
        payload: DeepTutorAskUserPayload,
        messageID: UUID,
        blockID: UUID
    ) -> Bool {
        if existing.toolCallID == toolCallID {
            return true
        }
        let existingPrompt = existing.payload.questions.first?.prompt ?? ""
        let incomingPrompt = payload.questions.first?.prompt ?? ""
        if existingPrompt == incomingPrompt,
           existingPrompt.isEmpty == false {
            return true
        }
        let existingKey = identityKey(
            messageID: messageID,
            blockID: blockID,
            toolCallID: existing.toolCallID,
            prompt: existingPrompt,
            optionLabels: existing.payload.questions.first?.options.map(\.label) ?? []
        )
        let incomingKey = identityKey(
            messageID: messageID,
            blockID: blockID,
            toolCallID: toolCallID,
            prompt: incomingPrompt,
            optionLabels: payload.questions.first?.options.map(\.label) ?? []
        )
        return existingKey == incomingKey
    }

    nonisolated static func payloadsMatch(
        _ lhs: DeepTutorAskUserPayload,
        _ rhs: DeepTutorAskUserPayload
    ) -> Bool {
        let leftPrompt = lhs.questions.first?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rightPrompt = rhs.questions.first?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if leftPrompt.isEmpty == false, leftPrompt == rightPrompt {
            return true
        }
        let leftLabels = lhs.questions.flatMap { $0.options.map(\.label) }
        let rightLabels = rhs.questions.flatMap { $0.options.map(\.label) }
        return promptHash(leftPrompt, optionLabels: leftLabels)
            == promptHash(rightPrompt, optionLabels: rightLabels)
    }

    nonisolated private static func promptHash(_ prompt: String, optionLabels: [String]) -> String {
        let seed = "\(prompt)|\(optionLabels.joined(separator: "|"))"
        return DeepTutorStableToolCallID.legacy(prefix: "ask-user-identity", seed: seed)
    }
}
