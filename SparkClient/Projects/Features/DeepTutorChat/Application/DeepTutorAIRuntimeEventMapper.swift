import Foundation

/// 将 `ChatAssistantPartialDelta` / 完成结果映射为 `DeepTutorStreamEvent` 增量。
struct DeepTutorAIRuntimeEventMapper: Sendable {
    private var lastAnswerLength = 0
    private var lastReasoningLength = 0
    private var startedToolCallIDs: Set<String> = []
    private var completedToolCallIDs: Set<String> = []
    private var askUserToolCallIDs: Set<String> = []
    private var memberSelectionToolCallIDs: Set<String> = []
    private var memberProfileToolCallIDs: Set<String> = []
    private var loggedAskUserMapFailures: Set<String> = []

    nonisolated mutating func events(from partial: ChatAssistantPartialDelta) -> [DeepTutorStreamEvent] {
        var events: [DeepTutorStreamEvent] = []

        if partial.answer.count > lastAnswerLength {
            let delta = String(partial.answer.dropFirst(lastAnswerLength))
            let filteredDelta = DeepTutorContentSanitizer.filterInternalThinking(from: delta)
            if filteredDelta.isEmpty == false,
               DeepTutorContentSanitizer.isToolPlanningNarration(filteredDelta) == false {
                events.append(.contentDelta(text: filteredDelta, callID: nil, round: nil))
            }
            lastAnswerLength = partial.answer.count
        }

        if let reasoning = partial.reasoning, reasoning.count > lastReasoningLength {
            let delta = String(reasoning.dropFirst(lastReasoningLength))
            if delta.isEmpty == false {
                events.append(.reasoningDelta(text: delta, callID: "reasoning", round: nil))
            }
            lastReasoningLength = reasoning.count
        }

        if let toolName = partial.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
           toolName.isEmpty == false,
           let toolCallID = partial.toolCallID,
           toolCallID.isEmpty == false {
            if startedToolCallIDs.contains(toolCallID) == false {
                startedToolCallIDs.insert(toolCallID)
                events.append(
                    .toolCallStarted(
                        callID: toolCallID,
                        toolName: toolName,
                        argsSummary: partial.toolArguments
                    )
                )
                appendAskUserEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_started",
                    into: &events
                )
                appendMemberSelectionEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_started",
                    into: &events
                )
            } else {
                appendAskUserEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_update",
                    into: &events
                )
                appendMemberSelectionEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_update",
                    into: &events
                )
            }

            if partial.kind == .tool,
               completedToolCallIDs.contains(toolCallID) == false,
               let toolContent = partial.toolContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               toolContent.isEmpty == false {
                completedToolCallIDs.insert(toolCallID)
                appendAskUserEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_completed",
                    into: &events
                )
                appendMemberSelectionEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    phase: "tool_completed",
                    into: &events
                )
                appendMemberProfileEventsIfNeeded(
                    toolName: toolName,
                    toolCallID: toolCallID,
                    partial: partial,
                    into: &events
                )
                let kind = DeepTutorAskUserNormalizer.canonicalToolName(for: toolName)
                events.append(
                    .toolResult(
                        callID: toolCallID,
                        payload: DeepTutorToolResultPayload(
                            kind: kind,
                            title: SparkToolName.displayName(for: toolName),
                            summary: toolContent,
                            metadata: partial.toolInvocationArguments
                        )
                    )
                )
            }
        }

        return events
    }

    nonisolated mutating func completionEvents(
        output: ChatOrchestratorOutput,
        resolvedModel: String?,
        promptTokens: Int?,
        completionTokens: Int?,
        finishReason: String?
    ) -> [DeepTutorStreamEvent] {
        var events: [DeepTutorStreamEvent] = []

        if output.text.count > lastAnswerLength {
            let delta = String(output.text.dropFirst(lastAnswerLength))
            let filteredDelta = DeepTutorContentSanitizer.filterInternalThinking(from: delta)
            if filteredDelta.isEmpty == false,
               DeepTutorContentSanitizer.isToolPlanningNarration(filteredDelta) == false {
                events.append(.contentDelta(text: filteredDelta, callID: nil, round: nil))
            }
            lastAnswerLength = output.text.count
        }

        if let reasoning = output.reasoningText,
           reasoning.count > lastReasoningLength {
            let delta = String(reasoning.dropFirst(lastReasoningLength))
            if delta.isEmpty == false {
                events.append(.reasoningDelta(text: delta, callID: "reasoning", round: nil))
            }
            lastReasoningLength = reasoning.count
        }

        var metadata: [String: String] = [:]
        if let resolvedModel { metadata["model"] = resolvedModel }
        if let finishReason { metadata["finishReason"] = finishReason }
        if let promptTokens { metadata["promptTokens"] = String(promptTokens) }
        if let completionTokens { metadata["completionTokens"] = String(completionTokens) }
        if let toolName = output.toolName { metadata["toolName"] = toolName }
        metadata["source"] = "ai-runtime"
        events.append(.result(metadata: metadata))
        return events
    }

    nonisolated mutating func errorEvent(message: String) -> DeepTutorStreamEvent {
        .error(message: message, turnTerminal: true)
    }

    nonisolated mutating func reset() {
        lastAnswerLength = 0
        lastReasoningLength = 0
        startedToolCallIDs = []
        completedToolCallIDs = []
        askUserToolCallIDs = []
        memberSelectionToolCallIDs = []
        memberProfileToolCallIDs = []
        loggedAskUserMapFailures = []
    }

    nonisolated private mutating func appendMemberProfileEventsIfNeeded(
        toolName: String,
        toolCallID: String,
        partial: ChatAssistantPartialDelta,
        into events: inout [DeepTutorStreamEvent]
    ) {
        guard DeepTutorQueryMemberProfileNormalizer.isQueryMemberProfileTool(toolName) else { return }
        guard memberProfileToolCallIDs.contains(toolCallID) == false else { return }
        guard let payload = DeepTutorQueryMemberProfileNormalizer.payload(from: partial) else { return }
        memberProfileToolCallIDs.insert(toolCallID)
        events.append(.memberProfileLoaded(payload: payload, toolCallID: toolCallID))
    }

    nonisolated private mutating func appendMemberSelectionEventsIfNeeded(
        toolName: String,
        toolCallID: String,
        partial: ChatAssistantPartialDelta,
        phase: String,
        into events: inout [DeepTutorStreamEvent]
    ) {
        guard DeepTutorMemberSelectionNormalizer.isMemberSelectionTool(toolName) else { return }
        guard memberSelectionToolCallIDs.contains(toolCallID) == false else { return }

        let arguments = DeepTutorMemberSelectionNormalizer.arguments(from: partial)
        let reason = DeepTutorMemberSelectionNormalizer.reason(from: arguments)
        memberSelectionToolCallIDs.insert(toolCallID)
        DeepTutorChatLog.memberSelectionToolRequested(
            conversationID: nil,
            assistantMessageID: nil,
            toolCallID: toolCallID,
            reason: reason,
            hasBoundMember: arguments["member_id"] != nil,
            boundMemberID: arguments["member_id"],
            allowedToolCount: 0
        )
        events.append(.memberSelectionRequested(reason: reason, arguments: arguments, toolCallID: toolCallID))
    }

    nonisolated private mutating func appendAskUserEventsIfNeeded(
        toolName: String,
        toolCallID: String,
        partial: ChatAssistantPartialDelta,
        phase: String,
        into events: inout [DeepTutorStreamEvent]
    ) {
        guard DeepTutorAskUserNormalizer.isAskUserTool(toolName) else { return }
        guard askUserToolCallIDs.contains(toolCallID) == false else { return }

        if let payload = askUserPayload(from: partial),
           let validated = DeepTutorAskUserNormalizer.validated(payload) {
            askUserToolCallIDs.insert(toolCallID)
            logAskUserRawArguments(partial: partial, toolCallID: toolCallID, phase: phase)
            let optionCounts = validated.questions.map { String($0.options.count) }.joined(separator: ",")
            let allowsOther = validated.questions.contains(where: \.allowFreeText)
            let mode = validated.questions.allSatisfy { $0.options.isEmpty && $0.allowFreeText } ? "free_text" : "options"
            DeepTutorChatLog.askUserMapped(
                phase: phase,
                toolName: toolName,
                toolCallID: toolCallID,
                questionCount: validated.questions.count,
                optionCounts: optionCounts,
                allowsOther: allowsOther,
                mode: mode
            )
            events.append(.askUser(payload: validated, toolCallID: toolCallID))
            return
        }

        if let payload = askUserPayload(from: partial) {
            let failureKey = "\(phase)#\(toolCallID)#invalid_payload"
            guard loggedAskUserMapFailures.contains(failureKey) == false else { return }
            loggedAskUserMapFailures.insert(failureKey)
            DeepTutorChatLog.askUserPayloadInvalid(
                messageID: nil,
                toolCallID: toolCallID,
                questionCount: payload.questions.count,
                optionCounts: payload.questions.map { String($0.options.count) }.joined(separator: ","),
                allowFreeText: payload.questions.contains(where: \.allowFreeText),
                promptPreview: payload.questions.first?.prompt ?? "-",
                reason: "prompt_invalid"
            )
        }

        let reason = askUserMapFailureReason(from: partial)
        guard shouldLogAskUserMapFailure(phase: phase, reason: reason) else { return }

        let failureKey = "\(phase)#\(toolCallID)#\(reason)"
        guard loggedAskUserMapFailures.contains(failureKey) == false else { return }
        loggedAskUserMapFailures.insert(failureKey)
        DeepTutorChatLog.askUserMapFailed(
            phase: phase,
            toolName: toolName,
            toolCallID: toolCallID,
            arguments: partial.toolInvocationArguments,
            rawArguments: partial.toolArguments,
            reason: reason
        )
    }

    nonisolated private func shouldLogAskUserMapFailure(phase: String, reason: String) -> Bool {
        switch reason {
        case "missing_arguments":
            return phase == "tool_completed"
        case "raw_invalid":
            return phase == "tool_completed"
        default:
            return phase != "tool_update"
        }
    }

    nonisolated private func logAskUserRawArguments(
        partial: ChatAssistantPartialDelta,
        toolCallID: String,
        phase: String
    ) {
        let raw = partial.toolArguments ?? ""
        let keys = partial.toolInvocationArguments?.keys.sorted().joined(separator: "|") ?? "-"
        DeepTutorChatLog.askUserRawArguments(
            toolCallID: toolCallID,
            phase: phase,
            rawLength: raw.count,
            raw: raw,
            argumentKeys: keys
        )
    }

    nonisolated private func askUserMapFailureReason(from partial: ChatAssistantPartialDelta) -> String {
        if partial.toolArguments?.isEmpty != false,
           partial.toolInvocationArguments?.isEmpty != false {
            return "missing_arguments"
        }
        if let raw = partial.toolArguments,
           raw.isEmpty == false,
           let data = raw.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) == nil {
            return "raw_invalid"
        }
        return "payload_normalization_failed"
    }

    nonisolated private func askUserPayload(from partial: ChatAssistantPartialDelta) -> DeepTutorAskUserPayload? {
        if let raw = partial.toolArguments,
           raw.isEmpty == false,
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let payload = DeepTutorAskUserNormalizer.payload(fromJSONObject: object) {
            return payload
        }
        if let args = partial.toolInvocationArguments, args.isEmpty == false {
            return mapAskUserPayload(from: args)
        }
        guard let raw = partial.toolArguments, raw.isEmpty == false else { return nil }
        let parsed = parseJSONObject(raw)
        return mapAskUserPayload(from: parsed)
    }

    nonisolated private func mapAskUserPayload(from arguments: [String: String]) -> DeepTutorAskUserPayload? {
        DeepTutorAskUserNormalizer.payload(from: arguments)
    }

    nonisolated private func parseJSONObject(_ raw: String) -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                result[key] = string
            } else if let array = value as? [String] {
                if JSONSerialization.isValidJSONObject(array),
                   let encoded = try? JSONSerialization.data(withJSONObject: array),
                   let json = String(data: encoded, encoding: .utf8) {
                    result[key] = json
                } else {
                    result[key] = array.joined(separator: "|")
                }
            } else if JSONSerialization.isValidJSONObject(value),
                      let encoded = try? JSONSerialization.data(withJSONObject: value),
                      let json = String(data: encoded, encoding: .utf8) {
                result[key] = json
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }
}

/// 过滤供应商误写入正文的内部思考片段与工具规划 narration。
enum DeepTutorContentSanitizer: Sendable {
    nonisolated static func filterInternalThinking(from text: String) -> String {
        var result = text
        let patterns = [
            #"（思考：[^）]*）"#,
            #"\(思考：[^)]*\)"#,
            #"（思考:[^）]*）"#,
            #"\(思考:[^)]*\)"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    nonisolated static func stripLeadingInternalThinking(from text: String) -> String {
        filterInternalThinking(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func isToolPlanningNarration(_ text: String) -> Bool {
        let trimmed = filterInternalThinking(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        let lowered = trimmed.lowercased()
        let markers = [
            "ask_user_question",
            "askuserquestion",
            "ask_user",
            "parameters",
            "required",
            "query_location",
            "query_weather",
            "tool_metadata",
            "selection_mode",
            "allows_other",
            "我将询问",
            "我需要调用",
            "接下来，获取",
            "确认是否符合",
            "工具的使用规则",
            "构造相关问询",
        ]
        if markers.contains(where: { lowered.contains($0.lowercased()) }) {
            return true
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return true
        }
        if trimmed.contains("tool_call") || trimmed.contains("toolCallID") {
            return true
        }
        return false
    }
}

enum DeepTutorAskUserAnswerMapper {
    nonisolated static func toolQuestionAnswer(
        deeptutorAnswers: [DeepTutorAskUserAnswer],
        payload: DeepTutorAskUserPayload
    ) -> ToolQuestionAnswer {
        let responses = deeptutorAnswers.compactMap { answer -> ToolQuestionResponse? in
            guard let question = payload.questions.first(where: { $0.id == answer.questionID }) else {
                return nil
            }
            let answerParts = Set(
                answer.text
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
            )
            let selectedOptions = question.options.filter {
                answerParts.contains($0.label) || answerParts.contains($0.id)
            }
            if selectedOptions.isEmpty == false {
                return ToolQuestionResponse(
                    questionID: question.id,
                    selectedOptionIDs: selectedOptions.map(\.id),
                    otherText: remainingCustomText(answer.text, selectedOptions: selectedOptions)
                )
            }
            return ToolQuestionResponse(
                questionID: question.id,
                selectedOptionIDs: [],
                otherText: answer.text
            )
        }
        return ToolQuestionAnswer(responses: responses)
    }

    nonisolated private static func remainingCustomText(
        _ text: String,
        selectedOptions: [DeepTutorAskUserOption]
    ) -> String? {
        var parts = text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let selectedLabels = Set(selectedOptions.map(\.label))
        parts.removeAll { selectedLabels.contains($0) }
        let custom = parts.joined(separator: ", ")
        return custom.isEmpty ? nil : custom
    }
}
