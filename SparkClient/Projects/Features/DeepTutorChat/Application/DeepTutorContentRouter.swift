import Foundation

/// 将 DeepTutor 流式事件分流为 trace / 正文 / askUser，对齐 DeepTutor-main `extractMessageSegments`。
enum DeepTutorContentRouter: Sendable {
    enum Segment: Equatable, Sendable {
        case text(String)
        case askUser(payload: DeepTutorAskUserPayload, toolCallID: String)
        case memberSelection(reason: String, arguments: [String: String], toolCallID: String)
    }

    struct RoutingSummary: Equatable, Sendable {
        var contentSegments: Int
        var traceSegments: Int
        var askUserSegments: Int
        var droppedNarrationLength: Int
        var finalAnswerLength: Int
        var reason: String
    }

    nonisolated static func segments(from message: DeepTutorMessage) -> [Segment] {
        var result: [Segment] = []
        var textBuffer = ""
        var seenAskUserToolCallIDs: Set<String> = []
        var seenMemberSelectionToolCallIDs: Set<String> = []
        var activeAskUserToolCallID: String?
        var activeMemberSelectionToolCallID: String?
        var hasAskUserToolCallStarted = false
        var hasMemberSelectionToolCallStarted = false

        func flushText() {
            let visible = message.capability == .deepQuestion
                ? DeepTutorQuizContentParser.visibleStreamingContent(from: textBuffer, capability: message.capability)
                : textBuffer
            let trimmed = sanitizedFinalAnswer(visible)
            if trimmed.isEmpty == false {
                result.append(.text(trimmed))
            }
            textBuffer = ""
        }

        for event in message.events {
            switch event {
            case let .contentDelta(text, _, _):
                if shouldDropContentDelta(
                    text,
                    activeAskUserToolCallID: activeAskUserToolCallID,
                    hasAskUserToolCallStarted: hasAskUserToolCallStarted,
                    hasPendingAskUser: activeAskUserToolCallID != nil
                ) {
                    continue
                }
                textBuffer += text

            case let .toolCallStarted(callID, toolName, _):
                if DeepTutorAskUserNormalizer.isAskUserTool(toolName) {
                    flushText()
                    hasAskUserToolCallStarted = true
                    activeAskUserToolCallID = callID
                } else if DeepTutorMemberSelectionNormalizer.isMemberSelectionTool(toolName) {
                    flushText()
                    hasMemberSelectionToolCallStarted = true
                    activeMemberSelectionToolCallID = callID
                }

            case let .askUser(payload, toolCallID):
                flushText()
                guard seenAskUserToolCallIDs.contains(toolCallID) == false else { continue }
                guard let validated = DeepTutorAskUserNormalizer.validated(payload) else { continue }
                seenAskUserToolCallIDs.insert(toolCallID)
                activeAskUserToolCallID = toolCallID
                result.append(.askUser(payload: validated, toolCallID: toolCallID))

            case let .askUserResolved(toolCallID, _):
                if activeAskUserToolCallID == toolCallID {
                    activeAskUserToolCallID = nil
                    hasAskUserToolCallStarted = false
                }

            case let .memberSelectionRequested(reason, arguments, toolCallID):
                flushText()
                guard seenMemberSelectionToolCallIDs.contains(toolCallID) == false else { continue }
                seenMemberSelectionToolCallIDs.insert(toolCallID)
                activeMemberSelectionToolCallID = toolCallID
                result.append(.memberSelection(reason: reason, arguments: arguments, toolCallID: toolCallID))

            case let .memberSelectionResolved(toolCallID, _, _):
                if activeMemberSelectionToolCallID == toolCallID {
                    activeMemberSelectionToolCallID = nil
                    hasMemberSelectionToolCallStarted = false
                }

            case let .toolResult(callID, payload) where DeepTutorAskUserNormalizer.isAskUserTool(payload.kind):
                guard let askPayload = DeepTutorAskUserNormalizer.payload(fromToolResult: payload),
                      let validated = DeepTutorAskUserNormalizer.validated(askPayload) else {
                    continue
                }
                flushText()
                guard seenAskUserToolCallIDs.contains(callID) == false else { continue }
                seenAskUserToolCallIDs.insert(callID)
                activeAskUserToolCallID = callID
                result.append(.askUser(payload: validated, toolCallID: callID))

            default:
                continue
            }
        }

        if textBuffer.isEmpty == false {
            flushText()
        } else if result.isEmpty {
            let fallbackSource = message.capability == .deepQuestion
                ? DeepTutorQuizContentParser.visibleStreamingContent(from: message.content, capability: message.capability)
                : message.content
            let fallback = sanitizedFinalAnswer(fallbackSource)
            if fallback.isEmpty == false {
                result.append(.text(fallback))
            }
        }

        return result
    }

    nonisolated static func finalAnswerContent(from message: DeepTutorMessage) -> String {
        segments(from: message)
            .compactMap { segment -> String? in
                if case .text(let text) = segment { return text }
                return nil
            }
            .joined(separator: "\n\n")
    }

    nonisolated static func routingSummary(for message: DeepTutorMessage) -> RoutingSummary {
        let routed = segments(from: message)
        let rawContentLength = message.events.compactMap { event -> Int? in
            if case let .contentDelta(text, _, _) = event { return text.count }
            return nil
        }.reduce(0, +) + message.content.count
        let finalAnswerLength = finalAnswerContent(from: message).count
        let askUserCount = routed.filter {
            if case .askUser = $0 { return true }
            return false
        }.count
        let reasoningLength = message.events.compactMap { event -> Int? in
            if case let .reasoningDelta(text, _, _) = event { return text.count }
            return nil
        }.reduce(0, +)

        let reason: String
        if askUserCount > 0, finalAnswerLength == 0 {
            reason = "pending_ask_user"
        } else if finalAnswerLength == 0, reasoningLength > 0 {
            reason = "reasoning_only_trace"
        } else if rawContentLength > finalAnswerLength {
            reason = "narration_filtered"
        } else {
            reason = "normal"
        }

        return RoutingSummary(
            contentSegments: routed.filter { if case .text = $0 { return true }; return false }.count,
            traceSegments: message.events.contains { if case .reasoningDelta = $0 { return true }; return false } ? 1 : 0,
            askUserSegments: askUserCount,
            droppedNarrationLength: max(0, rawContentLength - finalAnswerLength),
            finalAnswerLength: finalAnswerLength,
            reason: reason
        )
    }

    nonisolated static func hasPendingAskUser(_ message: DeepTutorMessage) -> Bool {
        DeepTutorTraceFormatter.hasPendingAskUser(message.events)
            || message.blocks.contains {
                if case let .askUser(payload) = $0.payload {
                    return payload.isResolved == false
                }
                return false
            }
    }

    nonisolated static func hasPendingMemberSelection(_ message: DeepTutorMessage) -> Bool {
        message.blocks.contains {
            guard case let .memberSelection(payload) = $0.payload else { return false }
            return payload.status == .pending || payload.status == .running
        }
    }

    nonisolated static func hasPendingUserInput(_ message: DeepTutorMessage) -> Bool {
        hasPendingAskUser(message) || hasPendingMemberSelection(message)
    }

    nonisolated static func shouldAcceptEmptyOutput(_ message: DeepTutorMessage, finishReason: String?) -> Bool {
        if finishReason == "awaiting_user_input" {
            return true
        }
        if hasPendingUserInput(message) {
            return true
        }
        let summary = routingSummary(for: message)
        if summary.askUserSegments > 0 {
            return true
        }
        if summary.reason == "reasoning_only_trace" {
            return true
        }
        let hasToolCalls = message.events.contains { event in
            if case .toolCallStarted = event { return true }
            return false
        }
        if hasToolCalls, summary.finalAnswerLength == 0 {
            return true
        }
        return false
    }

    nonisolated static func classifyEmptyOutput(
        message: DeepTutorMessage,
        finishReason: String?,
        textLen: Int,
        reasoningLen: Int,
        toolCallCount: Int,
        askUserPayloadCount: Int
    ) -> String {
        if finishReason == "awaiting_user_input" || hasPendingUserInput(message) {
            return "pending_ask_user"
        }
        if askUserPayloadCount > 0 {
            return "pending_ask_user"
        }
        if hasPendingMemberSelection(message) {
            return "pending_member_selection"
        }
        if reasoningLen > 0, textLen == 0 {
            return "reasoning_only_trace"
        }
        if toolCallCount > 0, textLen == 0 {
            return "tool_call_missing_from_accumulator"
        }
        if textLen == 0 {
            return "final_answer_empty_error"
        }
        return "runtime_error"
    }

    // MARK: - Private

    private nonisolated static func shouldDropContentDelta(
        _ text: String,
        activeAskUserToolCallID: String?,
        hasAskUserToolCallStarted: Bool,
        hasPendingAskUser: Bool
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if DeepTutorContentSanitizer.isToolPlanningNarration(trimmed) {
            return true
        }
        if hasPendingAskUser || hasAskUserToolCallStarted {
            return true
        }
        if activeAskUserToolCallID != nil {
            return true
        }
        return false
    }

    private nonisolated static func sanitizedFinalAnswer(_ text: String) -> String {
        DeepTutorContentSanitizer.stripLeadingInternalThinking(from: text)
    }
}
