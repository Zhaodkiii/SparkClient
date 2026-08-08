import Foundation

struct DeepTutorAskUserResumeContext: Sendable {
    let conversationID: UUID
    let assistantMessageID: UUID
    let precedingUserMessageID: UUID
    let toolCallID: String
    let toolName: String
    let toolArguments: String
    let assistantVisibleContent: String
    let reasoningContent: String?
    let toolResultText: String
    let originalUserPrompt: String
    let answerSummary: String
}

enum DeepTutorAskUserResumeBuilder: Sendable {
    nonisolated static func buildContext(
        assistant: DeepTutorMessage,
        precedingUser: DeepTutorMessage,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer]
    ) -> DeepTutorAskUserResumeContext? {
        guard let canonicalID = DeepTutorAskUserToolCallIDMatcher.canonicalToolCallID(
            in: assistant,
            submittedToolCallID: toolCallID
        ) else {
            return nil
        }

        var toolName = SparkToolName.askUserQuestion.rawValue
        var toolArguments = "{}"
        for event in assistant.events {
            if case let .toolCallStarted(callID, name, argsSummary) = event,
               callID == canonicalID || DeepTutorAskUserNormalizer.isAskUserTool(name) {
                toolName = name
                if let argsSummary, argsSummary.isEmpty == false {
                    toolArguments = argsSummary
                }
                break
            }
        }

        if toolArguments == "{}" {
            for event in assistant.events {
                if case let .askUser(payload, id) = event, id == canonicalID {
                    toolArguments = encodeAskUserArguments(payload)
                    break
                }
            }
        }

        let reasoning = assistant.events.compactMap { event -> String? in
            if case let .reasoningDelta(text, _, _) = event { return text }
            return nil
        }.joined()

        let askPayload = assistant.events.compactMap { event -> DeepTutorAskUserPayload? in
            if case let .askUser(payload, id) = event, id == canonicalID { return payload }
            return nil
        }.first

        let toolResultText: String
        if let askPayload {
            toolResultText = formatToolResultText(payload: askPayload, answers: answers)
        } else {
            toolResultText = answers.map(\.text).joined(separator: " | ")
        }

        return DeepTutorAskUserResumeContext(
            conversationID: assistant.conversationID,
            assistantMessageID: assistant.id,
            precedingUserMessageID: precedingUser.id,
            toolCallID: canonicalID,
            toolName: toolName,
            toolArguments: toolArguments,
            assistantVisibleContent: DeepTutorContentRouter.finalAnswerContent(from: assistant),
            reasoningContent: reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reasoning,
            toolResultText: toolResultText,
            originalUserPrompt: precedingUser.content,
            answerSummary: answers.map(\.text).joined(separator: "|")
        )
    }

    nonisolated static func buildLoopMessages(
        systemPrompt: String,
        visibleHistory: [DeepTutorMessage],
        context: DeepTutorAskUserResumeContext
    ) -> [AIRuntimeMessage] {
        var messages: [AIRuntimeMessage] = [
            AIRuntimeMessage(role: .system, content: systemPrompt),
        ]

        let history = visibleHistory
            .filter { $0.role != .system && $0.isDeleted == false && $0.id != context.assistantMessageID }
            .sorted { $0.createdAt < $1.createdAt }

        for message in history {
            let content = message.role == .assistant
                ? DeepTutorContentRouter.finalAnswerContent(from: message)
                : message.content
            guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
            messages.append(
                AIRuntimeMessage(
                    role: message.role == .user ? .user : .assistant,
                    content: content
                )
            )
        }

        messages.append(
            AIRuntimeMessage(
                role: .assistant,
                content: {
                    let trimmed = context.assistantVisibleContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }(),
                toolCalls: [
                    AIRuntimeToolCall(
                        id: context.toolCallID,
                        name: context.toolName,
                        arguments: context.toolArguments
                    ),
                ],
                reasoningContent: context.reasoningContent
            )
        )
        messages.append(
            AIRuntimeMessage(
                role: .tool,
                content: context.toolResultText,
                toolCallID: context.toolCallID,
                name: context.toolName
            )
        )
        return messages
    }

    nonisolated static func formatToolResultText(
        payload: DeepTutorAskUserPayload,
        answers: [DeepTutorAskUserAnswer]
    ) -> String {
        var lines = ["【系统】用户已提交追问答案。"]
        for answer in answers {
            guard let question = payload.questions.first(where: { $0.id == answer.questionID })
                ?? payload.questions.first else {
                lines.append("回答：\(answer.text)")
                continue
            }
            lines.append("问题：\(question.prompt)")
            lines.append("回答：\(answer.text)")
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func encodeAskUserArguments(_ payload: DeepTutorAskUserPayload) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
