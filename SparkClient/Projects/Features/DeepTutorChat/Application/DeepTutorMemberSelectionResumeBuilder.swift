import Foundation

struct DeepTutorMemberSelectionResumeContext: Sendable {
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
    let selectedMemberID: Int
    let selectedMemberName: String
}

enum DeepTutorMemberSelectionResumeBuilder: Sendable {
    nonisolated static func buildContext(
        assistant: DeepTutorMessage,
        precedingUser: DeepTutorMessage,
        toolCallID: String,
        memberID: Int,
        memberName: String
    ) -> DeepTutorMemberSelectionResumeContext? {
        let canonicalID = canonicalToolCallID(in: assistant, submittedToolCallID: toolCallID)
        guard canonicalID.isEmpty == false else { return nil }

        var toolName = SparkToolName.requestMemberSelection.rawValue
        var toolArguments = "{}"
        for event in assistant.events {
            if case let .toolCallStarted(callID, name, argsSummary) = event,
               callID == canonicalID || DeepTutorMemberSelectionNormalizer.isMemberSelectionTool(name) {
                toolName = name
                if let argsSummary, argsSummary.isEmpty == false {
                    toolArguments = argsSummary
                }
                break
            }
        }

        if toolArguments == "{}" {
            for event in assistant.events {
                if case let .memberSelectionRequested(reason, arguments, id) = event, id == canonicalID {
                    if let data = try? JSONSerialization.data(withJSONObject: arguments),
                       let json = String(data: data, encoding: .utf8) {
                        toolArguments = json
                    }
                    if reason.isEmpty == false, toolArguments == "{}" {
                        toolArguments = #"{"reason":"\#(reason)"}"#
                    }
                    break
                }
            }
        }

        let reasoning = assistant.events.compactMap { event -> String? in
            if case let .reasoningDelta(text, _, _) = event { return text }
            return nil
        }.joined()

        return DeepTutorMemberSelectionResumeContext(
            conversationID: assistant.conversationID,
            assistantMessageID: assistant.id,
            precedingUserMessageID: precedingUser.id,
            toolCallID: canonicalID,
            toolName: toolName,
            toolArguments: toolArguments,
            assistantVisibleContent: DeepTutorContentRouter.finalAnswerContent(from: assistant),
            reasoningContent: reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reasoning,
            toolResultText: formatToolResultText(memberID: memberID, memberName: memberName),
            originalUserPrompt: precedingUser.content,
            selectedMemberID: memberID,
            selectedMemberName: memberName
        )
    }

    nonisolated static func buildLoopMessages(
        systemPrompt: String,
        visibleHistory: [DeepTutorMessage],
        context: DeepTutorMemberSelectionResumeContext
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

    nonisolated static func formatToolResultText(memberID: Int, memberName: String) -> String {
        [
            L10n.text("tool.result.request_member_selection.completed"),
            #"{"selection_completed":true,"member_id":\#(memberID),"member_name":"\#(memberName)","instruction":"continue_conversation"}"#
        ].joined(separator: "\n")
    }

    nonisolated private static func canonicalToolCallID(
        in message: DeepTutorMessage,
        submittedToolCallID: String
    ) -> String {
        let trimmed = submittedToolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            if message.events.contains(where: { event in
                if case let .memberSelectionRequested(_, _, id) = event { return id == trimmed }
                if case let .toolCallStarted(callID, _, _) = event { return callID == trimmed }
                return false
            }) {
                return trimmed
            }
        }

        if let pending = message.events.compactMap({ event -> String? in
            if case let .memberSelectionRequested(_, _, id) = event { return id }
            return nil
        }).last {
            return pending
        }

        return trimmed
    }
}
